import asyncio, asyncssh
async def run():
  async with asyncssh.connect('178.105.51.242', username='root', password='AtmosVPN@Ger2024!', known_hosts=None) as conn:
    await conn.run('sed -i "s/Address = 10.8.0.1\/24/Address = 10.4.0.1\/24/g" /etc/wireguard/wg0.conf')
    await conn.run('systemctl restart wg-quick@wg0')
    res = await conn.run('ip addr show wg0')
    print(res.stdout)
asyncio.run(run())
