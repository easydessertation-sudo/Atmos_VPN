import asyncio, asyncssh, re

async def fix_server(ip, password, new_addr):
    async with asyncssh.connect(ip, username='root', password=password, known_hosts=None) as conn:
        # Stop first so SaveConfig writes current state, then we overwrite cleanly
        await conn.run('systemctl stop wg-quick@wg0', check=False)
        
        res = await conn.run('cat /etc/wireguard/wg0.conf')
        conf = res.stdout
        print(f'[{ip}] Before - Address:', next((l.strip() for l in conf.splitlines() if 'Address' in l), 'not found'))
        
        # Fix Address AND disable SaveConfig to prevent future revert
        conf = re.sub(r'Address\s*=\s*[\d.]+/24', f'Address = {new_addr}/24', conf)
        conf = re.sub(r'SaveConfig\s*=\s*true', 'SaveConfig = false', conf)
        
        with open('tmp_wg.conf', 'w', newline='\n') as f:
            f.write(conf)
        await asyncssh.scp('tmp_wg.conf', (conn, '/etc/wireguard/wg0.conf'))
        
        await conn.run('systemctl start wg-quick@wg0')
        await asyncio.sleep(2)
        
        res = await conn.run('ip addr show wg0')
        print(f'[{ip}] After  - {res.stdout.strip()}')

async def run():
    print('Fixing Finland server (hel-1)...')
    await fix_server('204.168.212.162', 'AtmosVPN@Hel2024!', '10.24.0.1')

asyncio.run(run())
