import asyncio, asyncssh
async def run():
  async with asyncssh.connect('178.105.51.242', username='root', password='AtmosVPN@Ger2024!', known_hosts=None) as conn:
    res = await conn.run('sed -i "s/Address = 10.8.0.1\/24/Address = 10.66.0.1\/24/" /etc/wireguard/wg0.conf; systemctl restart wg-quick@wg0; wg show')
    print(res.stdout)
asyncio.run(run())
