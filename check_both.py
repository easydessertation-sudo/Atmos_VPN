import asyncio, asyncssh
async def check_server(ip, password):
  async with asyncssh.connect(ip, username='root', password=password, known_hosts=None) as conn:
    res = await conn.run('ip addr show wg0')
    print(f'[{ip}] {res.stdout}')
async def run():
  await check_server('178.105.51.242', 'AtmosVPN@Ger2024!')
  await check_server('204.168.212.162', 'AtmosVPN@Hel2024!')
asyncio.run(run())
