import os
import asyncio
import logging
from dotenv import load_dotenv

load_dotenv()

# Set up logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

# Must set WG_SIMULATION=false to run this!
if os.environ.get("WG_SIMULATION", "true").lower() == "true":
    logger.error("WG_SIMULATION is set to true in .env! This script requires real SSH connections.")
    logger.error("Please set WG_SIMULATION=false and configure WG_SSH_USER and WG_SSH_KEY_PATH in .env before running this script.")
    exit(1)

from models import SessionLocal, VPNServer

# The bash script to install and configure WireGuard on any Ubuntu/Debian server
# This works identically on Hetzner and RackNerd VMs.
BASH_SETUP_SCRIPT = """
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q wireguard iptables ufw > /dev/null

# Generate Keys
cd /etc/wireguard
if [ ! -f privatekey ]; then
    umask 077
    wg genkey | tee privatekey | wg pubkey > publickey
fi

PRIVKEY=$(cat privatekey)
PUBKEY=$(cat publickey)

# Get the main network interface (e.g. eth0 or ens3)
ETH_IFACE=$(ip route ls default | awk '{print $5}' | head -n 1)

# Create the wg0 config
cat <<EOF > wg0.conf
[Interface]
Address = 10.0.0.1/24
SaveConfig = true
ListenPort = 51820
PrivateKey = $PRIVKEY
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $ETH_IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $ETH_IFACE -j MASQUERADE
EOF

# Enable IP forwarding (essential for VPN internet access)
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard-forward.conf
sysctl -p /etc/sysctl.d/99-wireguard-forward.conf > /dev/null

# Start and enable the WireGuard service
systemctl enable wg-quick@wg0 > /dev/null 2>&1
systemctl restart wg-quick@wg0

# Print the public key so the python script can capture it
echo "===WG_PUBKEY_RESULT==="
echo $PUBKEY
echo "===END_PUBKEY==="
"""

async def init_server(server, ssh_user, ssh_key_path):
    import asyncssh
    if not server.ip_address:
        logger.warning(f"Skipping server {server.id} - no IP address configured.")
        return None

    logger.info(f"Connecting to {server.name} ({server.ip_address})...")
    try:
        async with asyncssh.connect(
            server.ip_address,
            username=ssh_user,
            client_keys=[ssh_key_path],
            known_hosts=None
        ) as conn:
            logger.info(f"[{server.id}] Connected! Running WireGuard installation...")
            
            # Run the setup script
            result = await conn.run(BASH_SETUP_SCRIPT, check=True)
            
            # Extract the public key from the output
            output = result.stdout
            if "===WG_PUBKEY_RESULT===" in output:
                pubkey = output.split("===WG_PUBKEY_RESULT===")[1].split("===END_PUBKEY===")[0].strip()
                logger.info(f"[{server.id}] Successfully configured! Public Key: {pubkey}")
                return pubkey
            else:
                logger.error(f"[{server.id}] Failed to extract public key from output.")
                logger.debug(f"Output: {output}")
                return None

    except Exception as e:
        logger.error(f"[{server.id}] SSH Connection / Execution failed: {str(e)}")
        return None

async def main():
    ssh_user = os.environ.get("WG_SSH_USER", "root")
    ssh_key_path = os.environ.get("WG_SSH_KEY_PATH", "~/.ssh/id_rsa")
    ssh_key_path = os.path.expanduser(ssh_key_path)
    
    if not os.path.exists(ssh_key_path):
        logger.error(f"SSH key not found at {ssh_key_path}. Please check WG_SSH_KEY_PATH in .env")
        return

    db = SessionLocal()
    try:
        servers = db.query(VPNServer).filter(VPNServer.is_online == True).all()
        logger.info(f"Found {len(servers)} online servers in database. Starting initialization...")
        
        updated_count = 0
        for server in servers:
            pubkey = await init_server(server, ssh_user, ssh_key_path)
            if pubkey:
                server.wg_public_key = pubkey
                # We assume port 51820 is standard in the script
                server.wg_port = 51820 
                updated_count += 1
                
        if updated_count > 0:
            db.commit()
            logger.info(f"Success! Updated {updated_count} servers with their real WireGuard Public Keys.")
        else:
            logger.info("No servers were successfully updated.")
            
    finally:
        db.close()

if __name__ == "__main__":
    # asyncssh needs to run in an event loop
    asyncio.run(main())
