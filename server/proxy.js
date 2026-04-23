require('dotenv').config();

const http = require('http');
const WebSocket = require('ws');
const { URL } = require('url');
const fs = require('fs');
const path = require('path');

// ========== LOGGING SYSTEM ==========
const colors = {
    reset: '\x1b[0m',
    bright: '\x1b[1m',
    dim: '\x1b[2m',
    underscore: '\x1b[4m',
    blink: '\x1b[5m',
    reverse: '\x1b[7m',
    hidden: '\x1b[8m',
    
    fg: {
        black: '\x1b[30m',
        red: '\x1b[31m',
        green: '\x1b[32m',
        yellow: '\x1b[33m',
        blue: '\x1b[34m',
        magenta: '\x1b[35m',
        cyan: '\x1b[36m',
        white: '\x1b[37m',
        gray: '\x1b[90m',
        crimson: '\x1b[38m'
    },
    bg: {
        black: '\x1b[40m',
        red: '\x1b[41m',
        green: '\x1b[42m',
        yellow: '\x1b[43m',
        blue: '\x1b[44m',
        magenta: '\x1b[45m',
        cyan: '\x1b[46m',
        white: '\x1b[47m'
    }
};

const LOG_LEVELS = {
    ERROR: 0,
    WARN: 1,
    INFO: 2,
    DEBUG: 3
};

const LOG_CONFIG = {
    level: LOG_LEVELS[process.env.LOG_LEVEL?.toUpperCase() || 'INFO'] || LOG_LEVELS.INFO,
    enableColors: process.env.LOG_COLORS !== 'false',
    enableFile: process.env.LOG_FILE === 'true',
    logPath: process.env.LOG_PATH || path.join(process.cwd(), 'logs'),
    consoleCompact: process.env.LOG_CONSOLE_COMPACT !== 'false'
};

// Create log directory if file logging is enabled
if (LOG_CONFIG.enableFile && !fs.existsSync(LOG_CONFIG.logPath)) {
    fs.mkdirSync(LOG_CONFIG.logPath, { recursive: true });
}

function getTimestamp() {
    const now = new Date();
    return now.toISOString().replace('T', ' ').substring(0, 19);
}

function getShortTimestamp() {
    const now = new Date();
    return now.toLocaleTimeString('en-US', { hour12: false });
}

function colorize(text, color) {
    if (!LOG_CONFIG.enableColors) return text;
    return `${color}${text}${colors.reset}`;
}

function getLevelColor(level) {
    switch(level) {
        case 'ERROR': return colors.fg.red;
        case 'WARN': return colors.fg.yellow;
        case 'INFO': return colors.fg.green;
        case 'DEBUG': return colors.fg.cyan;
        default: return colors.fg.white;
    }
}

function getLevelBgColor(level) {
    switch(level) {
        case 'ERROR': return colors.bg.red;
        case 'WARN': return colors.bg.yellow;
        case 'INFO': return colors.bg.green;
        case 'DEBUG': return colors.bg.cyan;
        default: return colors.bg.white;
    }
}

function writeToFile(level, message, fullMessage) {
    if (!LOG_CONFIG.enableFile) return;
    
    const date = new Date();
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const logFile = path.join(LOG_CONFIG.logPath, `proxy-${year}-${month}-${day}.log`);
    
    const logEntry = `[${getTimestamp()}] [${level}] ${fullMessage}\n`;
    fs.appendFileSync(logFile, logEntry, 'utf8');
}

function log(level, message, ...args) {
    const levelValue = LOG_LEVELS[level];
    if (levelValue > LOG_CONFIG.level) return;
    
    const timestamp = LOG_CONFIG.consoleCompact ? getShortTimestamp() : getTimestamp();
    const levelColor = getLevelColor(level);
    const coloredLevel = colorize(level.padEnd(5), levelColor);
    
    let formattedMessage = message;
    if (args.length > 0) {
        formattedMessage = message.replace(/{}/g, () => {
            const arg = args.shift();
            return typeof arg === 'object' ? JSON.stringify(arg) : arg;
        });
        if (args.length > 0) {
            formattedMessage += ' ' + args.map(a => typeof a === 'object' ? JSON.stringify(a) : a).join(' ');
        }
    }
    
    const consoleMessage = LOG_CONFIG.consoleCompact 
        ? `${coloredLevel} ${timestamp} ${formattedMessage}`
        : `${coloredLevel} [${timestamp}] ${formattedMessage}`;
    
    console.log(consoleMessage);
    writeToFile(level, formattedMessage, `[${timestamp}] ${formattedMessage}`);
}

// Create logger object
const logger = {
    error: (msg, ...args) => log('ERROR', msg, ...args),
    warn: (msg, ...args) => log('WARN', msg, ...args),
    info: (msg, ...args) => log('INFO', msg, ...args),
    debug: (msg, ...args) => log('DEBUG', msg, ...args),
    
    // Special formatted logs
    connection: (id, direction, status, details = '') => {
        const statusColor = status === 'connected' ? colors.fg.green : colors.fg.red;
        const statusSymbol = status === 'connected' ? '▲' : '▼';
        logger.info(`${colorize(statusSymbol, statusColor)} ${direction.padEnd(7)} ${colorize(id, colors.fg.cyan)} ${status}${details ? ' ' + details : ''}`);
    },
    
    proxy: (from, to, type, id, data = '') => {
        const typeColor = type === 'msg' ? colors.fg.magenta : colors.fg.blue;
        const arrow = colorize('→', colors.fg.gray);
        logger.debug(`${colorize(from.padEnd(6), colors.fg.gray)} ${arrow} ${colorize(to.padEnd(6), colors.fg.gray)} ${colorize(type, typeColor)} ${colorize(id, colors.fg.cyan)}${data ? ' ' + data.substring(0, 50) : ''}`);
    },
    
    divider: (char = '=', length = 50) => {
        if (!LOG_CONFIG.consoleCompact) {
            console.log(colorize(char.repeat(length), colors.fg.gray));
        }
    }
};

// ========== PROXY SERVER ==========
const LOCAL_PORT = process.env.LOCAL_PORT || 8080;
const REMOTE_URL = process.env.REMOTE_URL;

if (!REMOTE_URL) {
    logger.error('REMOTE_URL environment variable is required');
    process.exit(1);
}

// Store local clients and their mappings to remote connections
const localClients = new Map();
let nextLocalId = 1;

function createLocalId() {
    return 'L' + (nextLocalId++) + '_' + Date.now();
}

// Create HTTP server for status page and WebSocket upgrade
const server = http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/') {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.write(`<!DOCTYPE html>
        <html>
        <head>
            <title>TheCards Local Proxy</title>
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
            <h1>TheCards Local Proxy</h1>
            <div class="status">
                <strong>Status:</strong> <span class="connected">RUNNING</span><br>
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
    logger.connection(localClientId, 'LOCAL', 'connected', `from ${req.socket.remoteAddress}`);
    
    const clientState = {
        localSocket,
        remoteSocket: null,
        roomId: null,
        hostId: null,
        messageQueue: []
    };
    
    localClients.set(localClientId, clientState);
    
    logger.debug(`Connecting to remote server for {}`, localClientId);
    
    let remoteSocket;
    try {
        remoteSocket = new WebSocket(REMOTE_URL);
        clientState.remoteSocket = remoteSocket;
    } catch (e) {
        logger.error(`Failed to create remote connection for {}: {}`, localClientId, e.message);
        localSocket.close(1011, "Internal Error");
        localClients.delete(localClientId);
        return;
    }
    
    remoteSocket.on('open', () => {
        logger.connection(localClientId, 'REMOTE', 'connected');
        
        while (clientState.messageQueue.length > 0) {
            const msgData = clientState.messageQueue.shift();
            try {
                remoteSocket.send(msgData);
                logger.proxy('QUEUE', 'REMOTE', 'flush', localClientId);
            } catch(e) {
                logger.error(`Error sending queued message: {}`, e.message);
            }
        }
    });
    
    remoteSocket.on('message', (data) => {
        try {
            const dataStr = data.toString();
            const msg = JSON.parse(dataStr);
            logger.proxy('REMOTE', 'LOCAL', msg.type || 'MSG', localClientId, dataStr.substring(0, 100));
            
            if (msg.type === 'ROOM_CREATED') {
                clientState.roomId = msg.code;
                clientState.hostId = localClientId;
                logger.info(`Room created: {} (host: {})`, msg.code, localClientId);
            } else if (msg.type === 'JOIN_SUCCESS') {
                clientState.roomId = msg.code;
                logger.info(`Joined room: {} (client: {})`, msg.code, localClientId);
            } else if (msg.type === 'ROOM_CLOSED') {
                clientState.roomId = null;
                clientState.hostId = null;
                logger.warn(`Room closed for client {}`, localClientId);
            }
            
            if (localSocket.readyState === WebSocket.OPEN) {
                localSocket.send(dataStr);
            }
        } catch (e) {
            logger.debug(`Forwarding raw message REMOTE → LOCAL`, localClientId);
            if (localSocket.readyState === WebSocket.OPEN) {
                localSocket.send(data.toString());
            }
        }
    });
    
    remoteSocket.on('close', (code, reason) => {
        logger.connection(localClientId, 'REMOTE', 'disconnected', `code:${code} reason:${reason || 'none'}`);
        
        if (localSocket.readyState === WebSocket.OPEN) {
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
        logger.error(`Remote socket error for {}: {}`, localClientId, err.message);
    });
    
    localSocket.on('message', (data) => {
        try {
            const dataStr = data.toString();
            try {
                const msg = JSON.parse(dataStr);
                logger.proxy('LOCAL', 'REMOTE', msg.type || 'MSG', localClientId, dataStr.substring(0, 100));
            } catch (e) {
                logger.proxy('LOCAL', 'REMOTE', 'RAW', localClientId, dataStr.substring(0, 100));
            }
            
            if (remoteSocket.readyState === WebSocket.OPEN) {
                remoteSocket.send(dataStr);
            } else if (remoteSocket.readyState === WebSocket.CONNECTING) {
                logger.debug(`Queuing message for remote (state: CONNECTING)`, localClientId);
                clientState.messageQueue.push(dataStr);
            } else {
                logger.warn(`Dropping message - remote not connected (state: {})`, remoteSocket.readyState);
            }
        } catch (e) {
            logger.error(`Error handling local message: {}`, e.message);
        }
    });
    
    localSocket.on('close', (code, reason) => {
        logger.connection(localClientId, 'LOCAL', 'disconnected', `code:${code}`);
        if (remoteSocket && (remoteSocket.readyState === WebSocket.OPEN || remoteSocket.readyState === WebSocket.CONNECTING)) {
            remoteSocket.close(1000, "Local client disconnected");
        }
        localClients.delete(localClientId);
    });
    
    localSocket.on('error', (err) => {
        logger.error(`Local socket error for {}: {}`, localClientId, err.message);
    });
});

// Start the proxy server
server.listen(LOCAL_PORT, '0.0.0.0', () => {
    console.log('\n' + colorize('═'.repeat(60), colors.fg.cyan));
    console.log(colorize('  TheCards Local Proxy Server', colors.bright + colors.fg.green));
    console.log(colorize('═'.repeat(60), colors.fg.cyan));
    console.log(`  ${colorize('Local WS:', colors.fg.yellow)}  ws://0.0.0.0:${LOCAL_PORT}`);
    console.log(`  ${colorize('Local HTTP:', colors.fg.yellow)} http://0.0.0.0:${LOCAL_PORT}`);
    console.log(`  ${colorize('Remote:', colors.fg.yellow)}     ${REMOTE_URL}`);
    console.log(`  ${colorize('Log Level:', colors.fg.yellow)}  ${Object.keys(LOG_LEVELS).find(k => LOG_LEVELS[k] === LOG_CONFIG.level) || 'INFO'}`);
    console.log(`  ${colorize('File Logging:', colors.fg.yellow)} ${LOG_CONFIG.enableFile ? colorize('ENABLED', colors.fg.green) : colorize('DISABLED', colors.fg.gray)}`);
    if (LOG_CONFIG.enableFile) {
        console.log(`  ${colorize('Log Path:', colors.fg.yellow)}     ${LOG_CONFIG.logPath}`);
    }
    console.log(colorize('═'.repeat(60), colors.fg.cyan));
    console.log(`\n  ${colorize('OK', colors.fg.green)} Proxy running! Connect your game client to:`);
    console.log(`   ${colorize(`ws://localhost:${LOCAL_PORT}`, colors.bright + colors.fg.cyan)}`);
    console.log(`  ${colorize('i', colors.fg.blue)} Status page: ${colorize(`http://localhost:${LOCAL_PORT}`, colors.fg.cyan)}`);
    console.log(colorize('═'.repeat(60), colors.fg.cyan) + '\n');
});

// Handle process termination
process.on('SIGINT', () => {
    logger.info('\nShutting down proxy...');
    
    for (const [id, data] of localClients) {
        if (data.remoteSocket && data.remoteSocket.readyState === WebSocket.OPEN) {
            data.remoteSocket.close();
        }
        if (data.localSocket && data.localSocket.readyState === WebSocket.OPEN) {
            data.localSocket.close();
        }
    }
    
    server.close(() => {
        logger.info('Proxy stopped.');
        process.exit(0);
    });
});