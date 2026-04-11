const http = require('http');
const WebSocket = require('ws');

const PORT = process.env.PORT || 8080;

// room code -> { hostId: string, clients: Map<clientId: string, socket>, code: string }
const rooms = new Map();
// clientId -> socket
const clients = new Map();

function generateCode() {
    let id = "";
    // const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    const chars = "0123456789";
    for(let i=0; i<5; i++){
        id += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return id;
}

let nextId = 1;

function createUniqueId() {
    return 'C' + (nextId++) + '_' + Math.random().toString(36).substr(2, 6);
}

const server = http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/') {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.write('<html><head><title>DevilBridge Rooms</title>');
        res.write('<style>body{font-family:sans-serif;padding:2rem} .room{background:#eee;padding:10px;margin-bottom:10px;border-radius:5px;box-shadow:0 2px 4px rgba(0,0,0,0.1);}</style></head><body>');
        res.write('<h1>Available Game Rooms</h1>');
        let activeRooms = Array.from(rooms.values());
        if (activeRooms.length === 0) {
            res.write('<p>No active rooms right now.</p>');
        } else {
            for (let room of activeRooms) {
                res.write(`<div class="room"><strong>Room Code:</strong> ${room.code} - <strong>Players:</strong> ${room.clients.size + 1}/4</div>`);
            }
        }
        res.write('</body></html>');
        res.end();
    } else {
        res.writeHead(404);
        res.end();
    }
});

const wss = new WebSocket.Server({ server });

wss.on('connection', (socket) => {
    const clientId = createUniqueId();
    clients.set(clientId, socket);
    socket.roomId = null; // Track which room this socket is in
    
    const sendMsg = (msg) => {
        try {
            socket.send(JSON.stringify(msg));
        } catch(e) {
            console.error("Error sending message to", clientId);
        }
    }

    sendMsg({ type: "HELLO", clientId });

    socket.on('message', (message) => {
        try {
            const msg = JSON.parse(message);
            handleMessage(socket, clientId, msg);
        } catch (e) {
            console.error("Failed to parse JSON:", message, e);
        }
    });

    socket.on('close', () => {
        console.log(`Client ${clientId} disconnected.`);
        clients.delete(clientId);
        if (socket.roomId && rooms.has(socket.roomId)) {
            const room = rooms.get(socket.roomId);
            if (room.hostId === clientId) {
                // Host left, destroy room
                console.log(`Host left room ${socket.roomId}, destroying room.`);
                for (let [cId, cSock] of room.clients.entries()) {
                    if (cId !== clientId) {
                        try {
                            cSock.send(JSON.stringify({ type: "ROOM_CLOSED" }));
                        } catch(e){}
                        cSock.roomId = null;
                    }
                }
                rooms.delete(socket.roomId);
            } else {
                room.clients.delete(clientId);
                const hostSock = clients.get(room.hostId);
                if (hostSock && hostSock.readyState === WebSocket.OPEN) {
                    hostSock.send(JSON.stringify({
                        type: "CLIENT_LEFT",
                        clientId: clientId
                    }));
                }
            }
        }
    });
    
    socket.on('error', (err) => {
        console.error(`Socket error from ${clientId}:`, err.message);
    });
});

function handleMessage(socket, clientId, msg) {
    switch (msg.type) {
        case "CREATE_ROOM":
            const code = generateCode();
            socket.roomId = code;
            rooms.set(code, {
                hostId: clientId,
                code: code,
                clients: new Map()
            });
            // Host is implicitly part of clients? Let's just track them separately or together.
            // rooms.get(code).clients.set(clientId, socket); => no, host is host.
            socket.send(JSON.stringify({ type: "ROOM_CREATED", code }));
            console.log(`Room ${code} created by ${clientId}`);
            break;

        case "JOIN_ROOM":
            if (msg.code && rooms.has(msg.code)) {
                const room = rooms.get(msg.code);
                if (room.clients.size >= 3) {
                    // Maximum 3 guests + 1 host
                    socket.send(JSON.stringify({ type: "ERROR", message: "Room is full" }));
                    return;
                }
                socket.roomId = msg.code;
                room.clients.set(clientId, socket);
                
                socket.send(JSON.stringify({ type: "JOIN_SUCCESS", code: msg.code }));
                
                // Notify host
                const hostSock = clients.get(room.hostId);
                if (hostSock && hostSock.readyState === WebSocket.OPEN) {
                    hostSock.send(JSON.stringify({ 
                        type: "CLIENT_JOINED", 
                        clientId: clientId,
                        name: msg.name // optional display name
                    }));
                }
                console.log(`Client ${clientId} joined room ${msg.code}`);
            } else {
                socket.send(JSON.stringify({ type: "ERROR", message: "Room not found" }));
            }
            break;
            
        case "HOST_MSG":
            // Host sending message to a specific client or all clients
            if (socket.roomId && rooms.has(socket.roomId)) {
                const room = rooms.get(socket.roomId);
                if (room.hostId === clientId) {
                    if (msg.targetId === "all") {
                        for (let [cId, cSock] of room.clients.entries()) {
                            if (cSock.readyState === WebSocket.OPEN) {
                                cSock.send(JSON.stringify({ type: "GAME_MSG", data: msg.data }));
                            }
                        }
                    } else {
                        const targetSock = room.clients.get(msg.targetId);
                        if (targetSock && targetSock.readyState === WebSocket.OPEN) {
                            targetSock.send(JSON.stringify({ type: "GAME_MSG", data: msg.data }));
                        }
                    }
                }
            }
            break;

        case "CLIENT_MSG":
            // Client sending message to host
            if (socket.roomId && rooms.has(socket.roomId)) {
                const room = rooms.get(socket.roomId);
                if (room.clients.has(clientId)) {
                    const hostSock = clients.get(room.hostId);
                    if (hostSock && hostSock.readyState === WebSocket.OPEN) {
                        hostSock.send(JSON.stringify({ 
                            type: "GUEST_MSG", 
                            clientId: clientId, 
                            data: msg.data 
                        }));
                    }
                }
            }
            break;
    }
}

server.listen(PORT, () => {
    console.log(`Relay Server listening on port ${PORT}`);
});
