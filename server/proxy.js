require('dotenv').config();

const http = require('http');
const WebSocket = require('ws');
const { URL } = require('url');

const LOCAL_PORT = process.env.LOCAL_PORT || 8080;
const REMOTE_URL = process.env.REMOTE_URL;

if (!REMOTE_URL) {
  console.error('Error: REMOTE_URL environment variable is required');
  process.exit(1);
}

// Store local clients and their mappings to remote connections
const localClients = new Map(); // localClientId -> { localSocket, remoteSocket, roomId, hostId }
let nextLocalId = 1;

function createLocalId() {
    return 'L' + (nextLocalId++) + '_' + Date.now();
}

// Create HTTP server for status page and WebSocket upgrade
const server = http.createServer((req, res) => {
    console.log(`${req.method} ${req.url}`);
    
    if (req.method === 'GET' && req.url === '/') {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.write(`<!DOCTYPE html>
        <html>
        <head>
            <title>DevilBridge Local Proxy</title>
            <style>
                body { font-family: monospace; padding: 2rem; background: #1e1e1e; color: #d4d4d4; }
                h1 { color: #4ec9b0; }
                .status { background: #2d2d2d; padding: 1rem; border-radius: 5px; margin: 1rem 0; }
                .connected { color: #4ec9b0; }
                .disconnected { color: #f48771; }
                .client { background: #252526; padding: 0.5rem; margin: 0.5rem 0; border-left: 3px solid #4ec9b0; }
                pre { margin: 0; }
            </style>
        </head>
        <body>
            <h1>DevilBridge Local Proxy</h1>
            <div class="status">
                <strong>Status:</strong> <span class="connected">● RUNNING</span><br>
                <strong>Remote Server:</strong> ${REMOTE_URL}<br>
                <strong>Active Clients:</strong> <span id="clientCount">${localClients.size}</span>
            </div>
            <h2>Active Connections</h2>
            <div id="clients">
                ${Array.from(localClients.entries()).map(([id, data]) => `
                    <div class="client">
                        <pre>ID: ${id}<br>Room: ${data.roomId || 'None'}<br>Host: ${data.hostId === id ? 'Yes' : 'No'}</pre>
                    </div>
                `).join('') || '<p>No active connections</p>'}
            </div>
            <p style="margin-top: 2rem; font-size: 0.8rem;">Connect using: <strong>ws://localhost:8080</strong></p>
        </body>
        </html>`);
        res.end();
    } else if (req.method === 'GET' && req.url === '/status') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            status: 'running',
            remoteServer: REMOTE_URL,
            activeClients: localClients.size,
            clients: Array.from(localClients.entries()).map(([id, data]) => ({
                id,
                roomId: data.roomId,
                isHost: data.hostId === id
            }))
        }));
    } else {
        res.writeHead(404);
        res.end('Not found');
    }
});

// WebSocket server for local clients
const wss = new WebSocket.Server({ server });

wss.on('connection', (localSocket, req) => {
    const localClientId = createLocalId();
    console.log(`[LOCAL] New client connected: ${localClientId}`);
    
    const clientState = {
        localSocket,
        remoteSocket: null,
        roomId: null,
        hostId: null,
        messageQueue: []
    };
    
    localClients.set(localClientId, clientState);
    
    console.log(`[REMOTE] Connecting to remote server for ${localClientId}...`);
    
    let remoteSocket;
    try {
        remoteSocket = new WebSocket(REMOTE_URL);
        clientState.remoteSocket = remoteSocket;
    } catch (e) {
        console.error(`[REMOTE] Failed to create connection for ${localClientId}:`, e);
        localSocket.close(1011, "Internal Error");
        localClients.delete(localClientId);
        return;
    }
    
    remoteSocket.on('open', () => {
        console.log(`[REMOTE] Connected for client ${localClientId}`);
        
        // Send any queued messages that were received while connecting
        while (clientState.messageQueue.length > 0) {
            const msgData = clientState.messageQueue.shift();
            try {
                remoteSocket.send(msgData);
            } catch(e) {
                console.error(`[REMOTE] Error sending queued message for ${localClientId}:`, e);
            }
        }
    });
    
    remoteSocket.on('message', (data) => {
        try {
            const dataStr = data.toString();
            const msg = JSON.parse(dataStr);
            console.log(`[PROXY] Remote -> Local (${localClientId}):`, msg.type);
            
            // Track room state from remote responses
            if (msg.type === 'ROOM_CREATED') {
                clientState.roomId = msg.code;
                clientState.hostId = localClientId;
            } else if (msg.type === 'JOIN_SUCCESS') {
                clientState.roomId = msg.code;
            } else if (msg.type === 'ROOM_CLOSED') {
                clientState.roomId = null;
                clientState.hostId = null;
            }
            
            if (localSocket.readyState === WebSocket.OPEN) {
                localSocket.send(dataStr);
            }
        } catch (e) {
            console.error('[PROXY] Error parsing remote message:', e);
            if (localSocket.readyState === WebSocket.OPEN) {
                localSocket.send(data.toString());
            }
        }
    });
    
    remoteSocket.on('close', (code, reason) => {
        console.log(`[REMOTE] Disconnected for client ${localClientId} - code: ${code}, reason: ${reason}`);
        
        if (localSocket.readyState === WebSocket.OPEN) {
            // Forward a graceful disconnect message first
            try {
                localSocket.send(JSON.stringify({
                    type: 'ERROR',
                    message: 'Connection to remote server lost'
                }));
                localSocket.close(1011, "Remote connection lost");
            } catch(e) {}
        }
        
        localClients.delete(localClientId);
    });
    
    remoteSocket.on('error', (err) => {
        console.error(`[REMOTE] Error for client ${localClientId}:`, err.message);
    });
    
    localSocket.on('message', (data) => {
        try {
            const dataStr = data.toString();
            try {
                const msg = JSON.parse(dataStr);
                console.log(`[PROXY] Local -> Remote (${localClientId}):`, msg.type);
            } catch (e) {
                console.log(`[PROXY] Local -> Remote (${localClientId}): [Invalid JSON]`);
            }
            
            if (remoteSocket.readyState === WebSocket.OPEN) {
                remoteSocket.send(dataStr);
            } else if (remoteSocket.readyState === WebSocket.CONNECTING) {
                console.log(`[PROXY] Queuing message for remote...`);
                clientState.messageQueue.push(dataStr);
            } else {
                console.log(`[PROXY] Dropping message - remote not connected`);
            }
        } catch (e) {
            console.error('[PROXY] Error handling local message:', e);
        }
    });
    
    localSocket.on('close', (code, reason) => {
        console.log(`[LOCAL] Client disconnected: ${localClientId}`);
        if (remoteSocket && (remoteSocket.readyState === WebSocket.OPEN || remoteSocket.readyState === WebSocket.CONNECTING)) {
            remoteSocket.close(1000, "Local client disconnected");
        }
        localClients.delete(localClientId);
    });
    
    localSocket.on('error', (err) => {
        console.error(`[LOCAL] Socket error for ${localClientId}:`, err.message);
    });
});

// Start the proxy server
server.listen(LOCAL_PORT, () => {
    console.log('=' .repeat(60));
    console.log('DevilBridge Local Proxy Server');
    console.log('=' .repeat(60));
    console.log(`Local WebSocket endpoint: ws://localhost:${LOCAL_PORT}`);
    console.log(`Local HTTP endpoint: http://localhost:${LOCAL_PORT}`);
    console.log(`Remote server: ${REMOTE_URL}`);
    console.log('=' .repeat(60));
    console.log('\nProxy is running! Connect your game client to:');
    console.log(`   ws://localhost:${LOCAL_PORT}`);
    console.log('\nStatus page available at:');
    console.log(`   http://localhost:${LOCAL_PORT}`);
    console.log('=' .repeat(60));
});

// Handle process termination
process.on('SIGINT', () => {
    console.log('\nShutting down proxy...');
    
    // Close all connections
    for (const [id, data] of localClients) {
        if (data.remoteSocket && data.remoteSocket.readyState === WebSocket.OPEN) {
            data.remoteSocket.close();
        }
        if (data.localSocket && data.localSocket.readyState === WebSocket.OPEN) {
            data.localSocket.close();
        }
    }
    
    server.close(() => {
        console.log('Proxy stopped.');
        process.exit(0);
    });
});