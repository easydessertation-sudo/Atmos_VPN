import asyncio, asyncssh, re
async def fix_server(ip, password, old_addr, new_addr):
  async with asyncssh.connect(ip, username='root', password=password, known_hosts=None) as conn:
    res = await conn.run('cat /etc/wireguard/wg0.conf')
    conf = res.stdout
    conf = re.sub(r'Address\s*=\s*[\d\.]+/24', f'Address = {new_addr}/24', conf)
    with open('tmp.conf', 'w') as f: f.write(conf)
    await asyncssh.scp('tmp.conf', (conn, '/etc/wireguard/wg0.conf'))
    await conn.run('systemctl restart wg-quick@wg0; ip addr show wg0')
    print(f'Fixed {ip}')
async def run():
  await fix_server('178.105.51.242', 'AtmosVPN@Ger2024!', '10.8.0.1', '10.4.0.1')
  await fix_server('204.168.212.162', 'AtmosVPN@Hel2024!', '10.8.0.1', '10.24.0.1')
asyncio.run(run())
