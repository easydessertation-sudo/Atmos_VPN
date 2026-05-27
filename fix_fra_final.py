import asyncio, asyncssh
async def run():
  async with asyncssh.connect('178.105.51.242', username='root', password='AtmosVPN@Ger2024!', known_hosts=None) as conn:
    res = await conn.run('ip addr show wg0')
    print(res.stdout)
asyncio.run(run())
