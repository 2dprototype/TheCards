const net = require('net');

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

const server = net.createServer((socket) => {
    socket.setEncoding('utf8');
    const clientId = createUniqueId();
    clients.set(clientId, socket);
    socket.roomId = null; // Track which room this socket is in
    
    // Simple newline delimited JSON
    let buffer = "";
    
    const sendMsg = (msg) => {
        try {
            socket.write(JSON.stringify(msg) + "\n");
        } catch(e) {
            console.error("Error sending message to", clientId);
        }
    }

    sendMsg({ type: "HELLO", clientId });

    socket.on('data', (data) => {
        buffer += data;
        let lines = buffer.split("\n");
        buffer = lines.pop(); // keep last incomplete part
        
        for (let line of lines) {
            if (line.trim().length === 0) continue;
            try {
                const msg = JSON.parse(line);
                handleMessage(socket, clientId, msg);
            } catch (e) {
                console.error("Failed to parse JSON:", line, e);
            }
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
                            cSock.write(JSON.stringify({ type: "ROOM_CLOSED" }) + "\n");
                        } catch(e){}
                        cSock.roomId = null;
                    }
                }
                rooms.delete(socket.roomId);
            } else {
                room.clients.delete(clientId);
                const hostSock = clients.get(room.hostId);
                if (hostSock) {
                    hostSock.write(JSON.stringify({
                        type: "CLIENT_LEFT",
                        clientId: clientId
                    }) + "\n");
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
            socket.write(JSON.stringify({ type: "ROOM_CREATED", code }) + "\n");
            console.log(`Room ${code} created by ${clientId}`);
            break;

        case "JOIN_ROOM":
            if (msg.code && rooms.has(msg.code)) {
                const room = rooms.get(msg.code);
                if (room.clients.size >= 3) {
                    // Maximum 3 guests + 1 host
                    socket.write(JSON.stringify({ type: "ERROR", message: "Room is full" }) + "\n");
                    return;
                }
                socket.roomId = msg.code;
                room.clients.set(clientId, socket);
                
                socket.write(JSON.stringify({ type: "JOIN_SUCCESS", code: msg.code }) + "\n");
                
                // Notify host
                const hostSock = clients.get(room.hostId);
                if (hostSock) {
                    hostSock.write(JSON.stringify({ 
                        type: "CLIENT_JOINED", 
                        clientId: clientId,
                        name: msg.name // optional display name
                    }) + "\n");
                }
                console.log(`Client ${clientId} joined room ${msg.code}`);
            } else {
                socket.write(JSON.stringify({ type: "ERROR", message: "Room not found" }) + "\n");
            }
            break;
            
        case "HOST_MSG":
            // Host sending message to a specific client or all clients
            if (socket.roomId && rooms.has(socket.roomId)) {
                const room = rooms.get(socket.roomId);
                if (room.hostId === clientId) {
                    if (msg.targetId === "all") {
                        for (let [cId, cSock] of room.clients.entries()) {
                            cSock.write(JSON.stringify({ type: "GAME_MSG", data: msg.data }) + "\n");
                        }
                    } else {
                        const targetSock = room.clients.get(msg.targetId);
                        if (targetSock) {
                            targetSock.write(JSON.stringify({ type: "GAME_MSG", data: msg.data }) + "\n");
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
                    if (hostSock) {
                        hostSock.write(JSON.stringify({ 
                            type: "GUEST_MSG", 
                            clientId: clientId, 
                            data: msg.data 
                        }) + "\n");
                    }
                }
            }
            break;
    }
}

server.listen(PORT, () => {
    console.log(`Relay Server listening on port ${PORT}`);
});
