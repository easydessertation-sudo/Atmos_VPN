import asyncio, asyncssh, re

async def fix_server(ip, password, new_addr):
    async with asyncssh.connect(ip, username='root', password=password, known_hosts=None) as conn:
        # Step 1: Stop wg-quick cleanly (this triggers SaveConfig to write current state)
        await conn.run('systemctl stop wg-quick@wg0', check=False)
        
        # Step 2: Read the (now saved) config
        res = await conn.run('cat /etc/wireguard/wg0.conf')
        conf = res.stdout
        print(f'[{ip}] Current Address line:', next((l for l in conf.splitlines() if 'Address' in l), 'not found'))
        
        # Step 3: Replace the Address AND remove SaveConfig (it causes the revert)
        conf = re.sub(r'Address\s*=\s*[\d.]+/24', f'Address = {new_addr}/24', conf)
        conf = re.sub(r'SaveConfig\s*=\s*true', 'SaveConfig = false', conf)
        
        # Step 4: Write the corrected config via SCP
        with open('tmp_wg.conf', 'w', newline='\n') as f:
            f.write(conf)
        await asyncssh.scp('tmp_wg.conf', (conn, '/etc/wireguard/wg0.conf'))
        
        # Step 5: Start wg-quick fresh
        await conn.run('systemctl start wg-quick@wg0')
        await asyncio.sleep(2)
        
        # Step 6: Verify
        res = await conn.run('ip addr show wg0')
        print(f'[{ip}] After fix:', res.stdout.strip())

async def run():
    print('Fixing Germany server (fra-1)...')
    await fix_server('178.105.51.242', 'AtmosVPN@Ger2024!', '10.4.0.1')

asyncio.run(run())
