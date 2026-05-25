"""
Fix Dallas WireGuard Server:
1. Backup old wg0.conf
2. Write a clean wg0.conf with no duplicates (based on DB truth)
3. Reload WireGuard with the clean config (no downtime)
"""
import asyncio
import asyncssh

CLEAN_CONF = """[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = qFoUrnIbXYcy9wtuEXeyBHN23eumRnuZOEK+AlnQF1U=
SaveConfig = false

# NAT: forward VPN traffic to internet
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

[Peer]
PublicKey = xbp+oVJ1Ltsxptso5o9ofV7yMtf0N0paZdpdsQed9hg=
AllowedIPs = 10.8.0.2/32

[Peer]
PublicKey = +Bbbwp3UjtOUDZtwrHBwCOaCbCpvWyQLfoTBrXP5ChY=
AllowedIPs = 10.8.0.3/32

[Peer]
PublicKey = 4rePf87Pt8B+uywtAnuepnAP2foynykSBMhIKG7+WTU=
AllowedIPs = 10.8.0.4/32, 10.8.0.5/32

[Peer]
PublicKey = W2C7OFQdGXW85l45c+09wkb3TAZZ05fHMPQ0z6YNK1Y=
AllowedIPs = 10.8.0.7/32

[Peer]
PublicKey = 8J3Y3UOH4C+J/blqo0PMzlojS1YBuaiDIJqJ+aFjTBU=
AllowedIPs = 10.8.0.8/32

[Peer]
PublicKey = 3YNTzen42HERRCfs5JZdbEBcRQFX62KgZqNnFCz3zRE=
AllowedIPs = 10.8.0.9/32

[Peer]
PublicKey = hfPGFz135bYxz9eROoL8nXU7WVZv0PNE6iDl037ztmo=
AllowedIPs = 10.8.0.10/32

[Peer]
PublicKey = P7OKAloHF/KYUQAwHPE2lJ4QRwIRT8vyOBqVit2fwQc=
AllowedIPs = 10.8.0.11/32

[Peer]
PublicKey = c3EPkTtloNb4pkVe4y9gIRxHBl+IllRnX4V9dtLzXTA=
AllowedIPs = 10.8.0.12/32
"""


async def fix_dallas():
    server_ip = '198.23.209.178'
    password   = 'cL47Nmm6Ha6YyQ4T5g'

    async with asyncssh.connect(
        server_ip, username='root', password=password,
        known_hosts=None, connect_timeout=30
    ) as conn:

        # 1. Backup
        r = await conn.run('cp /etc/wireguard/wg0.conf /etc/wireguard/wg0.conf.bak', check=False)
        print(f'[1] Backup created (rc={r.returncode})')

        # 2. Write clean config via heredoc through stdin
        write_cmd = 'cat > /etc/wireguard/wg0.conf'
        r = await conn.run(write_cmd, input=CLEAN_CONF, check=False)
        print(f'[2] Config written (rc={r.returncode})')
        if r.stderr:
            print('    stderr:', r.stderr)

        # 3. Verify file
        r = await conn.run('wc -l /etc/wireguard/wg0.conf && echo "---" && cat /etc/wireguard/wg0.conf', check=False)
        print('[3] Written config:')
        print(r.stdout)

        # 4. Reload WireGuard live (no restart needed — syncconf replaces peer list)
        #    wg-quick strip strips comments/PostUp/PostDown so wg syncconf accepts it
        strip_and_sync = (
            'wg-quick strip wg0 > /tmp/wg0_stripped.conf && '
            'wg syncconf wg0 /tmp/wg0_stripped.conf && '
            'rm /tmp/wg0_stripped.conf'
        )
        r = await conn.run(strip_and_sync, check=False)
        print(f'[4] WireGuard reloaded (rc={r.returncode})')
        if r.stdout: print('    stdout:', r.stdout)
        if r.stderr: print('    stderr:', r.stderr)

        # 5. Final verification
        r = await conn.run('wg show wg0', check=False)
        print('[5] Live wg0 state:')
        print(r.stdout)
        
        r = await conn.run('wg show wg0 peers | wc -l', check=False)
        print(f'[5] Total live peers: {r.stdout.strip()}')


asyncio.run(fix_dallas())
print('Done.')
