import asyncio, asyncssh
async def run():
  async with asyncssh.connect('204.168.212.162', username='root', password='AtmosVPN@Hel2024!', known_hosts=None) as conn:
    res = await conn.run('cat /etc/wireguard/wg0.conf')
    print(res.stdout)
asyncio.run(run())
