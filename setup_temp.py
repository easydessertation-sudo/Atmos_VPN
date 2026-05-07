import asyncio
import asyncssh
import sys

SERVER_SCRIPT = """
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q wireguard iptables ufw > /dev/null

cd /etc/wireguard
if [ ! -f privatekey ]; then
    umask 077
    wg genkey | tee privatekey | wg pubkey > publickey
fi

PRIVKEY=$(cat privatekey)
PUBKEY=$(cat publickey)
ETH_IFACE=$(ip route ls default | awk '{print $5}' | head -n 1)

cat <<EOF > wg0.conf
[Interface]
Address = 10.0.0.1/24
SaveConfig = true
ListenPort = 51820
PrivateKey = $PRIVKEY
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $ETH_IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $ETH_IFACE -j MASQUERADE
EOF

echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard-forward.conf
sysctl -p /etc/sysctl.d/99-wireguard-forward.conf > /dev/null

systemctl enable wg-quick@wg0 > /dev/null 2>&1
systemctl restart wg-quick@wg0

echo "===WG_PUBKEY_RESULT==="
echo $PUBKEY
echo "===END_PUBKEY==="
"""

async def run_setup(ip, pwd, name):
    print(f"Starting setup for {name} ({ip})...")
    try:
        async with asyncssh.connect(ip, username="root", password=pwd, known_hosts=None) as conn:
            print(f"Connected to {name}! Running WireGuard installation...")
            result = await conn.run(SERVER_SCRIPT, check=True)
            output = result.stdout
            if "===WG_PUBKEY_RESULT===" in output:
                pubkey = output.split("===WG_PUBKEY_RESULT===")[1].split("===END_PUBKEY===")[0].strip()
                print(f"{name} Successfully configured! Public Key: {pubkey}")
                return pubkey
            else:
                print(f"{name} Failed to get pubkey. Output: {output}")
                return None
    except Exception as e:
        print(f"{name} setup failed: {e}")
        return None

async def main():
    sys.path.append(".")
    from models import SessionLocal, VPNServer
    
    servers_to_setup = [
        {"id": "sgp-1", "ip": "149.28.158.97", "pwd": "B5z{C=S!V!d8nF3K"},
        {"id": "jnb-1", "ip": "139.84.245.35", "pwd": "iD3=XCfxe[V)Xg6j"},
        {"id": "fra-1", "ip": "64.177.68.146", "pwd": "5[Mq@Ku]TaDYzG--"}
    ]
    
    db = SessionLocal()
    
    # Create Johannesburg if it doesn't exist
    jnb = db.query(VPNServer).filter(VPNServer.id == "jnb-1").first()
    if not jnb:
        jnb = VPNServer(
            id="jnb-1", 
            name="Johannesburg", 
            city="Johannesburg", 
            country="South Africa", 
            country_code="za", 
            flag="🇿🇦",
            is_online=True,
            capacity_mbps=1000
        )
        db.add(jnb)
        db.commit()

    for srv in servers_to_setup:
        pubkey = await run_setup(srv["ip"], srv["pwd"], srv["id"])
        if pubkey:
            db_srv = db.query(VPNServer).filter(VPNServer.id == srv["id"]).first()
            if db_srv:
                db_srv.ip_address = srv["ip"]
                db_srv.wg_public_key = pubkey
                db_srv.wg_port = 51820
                print(f"Saved {srv['id']} to database.")
    db.commit()
    db.close()
    print("All done!")

if __name__ == "__main__":
    asyncio.run(main())
