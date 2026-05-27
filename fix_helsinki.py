import asyncio, asyncssh
async def run():
  async with asyncssh.connect('204.168.212.162', username='root', password='AtmosVPN@Hel2024!', known_hosts=None) as conn:
    res = await conn.run('sed -i "s/Address = 10.8.0.1\/24/Address = 10.24.0.1\/24/" /etc/wireguard/wg0.conf; systemctl restart wg-quick@wg0; wg show')
    print(res.stdout)
asyncio.run(run())
