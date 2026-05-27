import asyncio, asyncssh
async def run():
  async with asyncssh.connect('178.105.51.242', username='root', password='AtmosVPN@Ger2024!', known_hosts=None) as conn:
    res = await conn.run('cat /etc/wireguard/wg0.conf')
    conf = res.stdout
    conf = conf.replace('Address = 10.8.0.1/24', 'Address = 10.4.0.1/24')
    conf = conf.replace('Address = 10.132.0.1/24', 'Address = 10.4.0.1/24')
    conf = conf.replace('Address = 10.66.0.1/24', 'Address = 10.4.0.1/24')
    await conn.run(f"echo '{conf}' > /etc/wireguard/wg0.conf")
    await conn.run('systemctl restart wg-quick@wg0; ip addr show wg0')
asyncio.run(run())
