#!/bin/bash

# Check if maintenance mode is currently enabled
echo "Current maintenance mode status:"
MAINTENANCE_MODE=true python3 -c "from api_config import MAINTENANCE_MODE; print(f'Maintenance mode is: {MAINTENANCE_MODE}')"

echo ""
echo "Testing websocket in normal mode:"
# Test the websocket connection (should work normally)
MAINTENANCE_MODE=false python3 -c "
import asyncio
from aiohttp import web
from api import init_app

async def test():
    app = await init_app()
    print('API initialized successfully')
    print('Maintenance mode is disabled, WebSocket connections should work normally')
    return app

if __name__ == '__main__':
    asyncio.run(test())
"

echo ""
echo "Testing websocket in maintenance mode:"
# Test the websocket in maintenance mode
MAINTENANCE_MODE=true python3 -c "
import asyncio
from aiohttp import web
from api import init_app

async def test():
    app = await init_app()
    print('API initialized successfully')
    print('Maintenance mode is enabled, WebSocket connections should be rejected')
    return app

if __name__ == '__main__':
    asyncio.run(test())
"

echo ""
echo "Testing HTTP server in maintenance mode:"
# Start the server in maintenance mode to test HTTP serving
# This will run in background for 5 seconds
MAINTENANCE_MODE=true python3 -c "
import asyncio
import time
from aiohttp import web
from api import init_app

async def test():
    app = await init_app()
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, 'localhost', 8080)
    print('Starting server in maintenance mode at http://localhost:8080')
    await site.start()
    print('Serving static files from build/web/ directory')
    print('You can open http://localhost:8080 in your browser now')
    print('Server will shut down in 10 seconds...')
    for i in range(10, 0, -1):
        print(f'{i}...')
        await asyncio.sleep(1)
    print('Shutting down server')
    await runner.cleanup()

if __name__ == '__main__':
    asyncio.run(test())
"