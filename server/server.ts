import express from 'express';
import bodyParser from 'body-parser';
import http from 'http';
import fs from 'fs';
import path from 'path';
import { performance } from 'perf_hooks';

type SkyFile = Record<string, string>;

interface Constellation {
    name: string;
    epithet: string;
}

const PORT = 8080;
const HOST = process.env['HOST'] ?? '127.0.0.1';
const app = express();

app.use(express.static(path.join(__dirname, '../public')));
app.use(bodyParser.json());

const readFile = (path: string): Promise<Buffer> => {
    return new Promise((resolve, reject) => {
        fs.readFile(path, (error, data) => {
            if (error != null) {
                reject(error);
            }
            resolve(data);
        });
    });
};

const stat = (path: string): Promise<fs.Stats> => {
    return new Promise((resolve, reject) => {
        fs.stat(path, (err, stats) => {
            if (err != null) {
                reject(err);
            }
            resolve(stats);
        });
    });
};

/**
 * Get a list of all the filenames in the top level of a directory.
 * @param dir_path The path to the directory to read
 */
const readDir = (dir_path: string): Promise<string[]> => {
    return new Promise((resolve, reject) => {
        fs.readdir(dir_path, async (err, files) => {
            if (err != null) {
                reject(err);
            }
            const filenames: string[] = [];
            for (const name of files) {
                const full_path = path.join(dir_path, name);
                const stats = await stat(full_path);
                if (!stats.isDirectory()) {
                    filenames.push(full_path);
                }
            }
            resolve(filenames);
        });
    });
};

const parseSkyFile = (data: string): SkyFile => {
    const fields: SkyFile = {};
    const lines = data.includes('\r\n') ? data.split('\r\n') : data.split('\n');
    for (let i = 0; i < lines.length; i += 1) {
        const current_line = lines[i];
        if (current_line.startsWith('@')) {
            if (current_line.includes('=') && !current_line.includes('=|')) {
                const [field_name, field_value] = current_line
                    .substring(1)
                    .split('=')
                    .map(s => s.trim());
                fields[field_name] = field_value;
            } else if (current_line.includes('=|')) {
                // Get each line after this as a multiline string
                // Keep going until the next new symbol
                const field_name = current_line.substring(1).split('=|')[0].trim();
                let field_value = '';
                i += 1;
                while (i < lines.length && !lines[i].startsWith('@') && !lines[i].startsWith('#')) {
                    field_value = field_value.concat('\n', lines[i]);
                    i += 1;
                }
                fields[field_name] = field_value;
                i -= 1;
            }
        } else if (current_line.startsWith('#')) {
            const field_name = current_line.substring(1);
            fields[field_name] = 'true';
        }
    }
    return fields;
};

const readConstellationFiles = async (): Promise<Constellation[]> => {
    const sky_files = await readDir(path.join(__dirname, '..', 'prepare-data', 'constellations', 'iau'));
    const result: Constellation[] = [];
    for (const filename of sky_files) {
        const file = await readFile(filename);
        const data = parseSkyFile(file.toString());
        const const_name = data['name'];

        console.log(const_name);

        result.push({
            name: const_name,
            epithet: data['epithet'],
        });
    }

    return result;
};

const main = async () => {
    const const_bin = await readFile(path.join(__dirname, 'const_data.bin'));

    const const_parse_start = performance.now();
    const constellations: Constellation[] = await readConstellationFiles();
    const const_parse_end = performance.now();

    console.log(`Constellation parsing took ${const_parse_end - const_parse_start} ms`);
    app.get('/', async (req, res) => {
        res.sendFile(path.join(__dirname, 'index.html'));
    });

    app.get('/stars', async (req, res) => {
        const response_start = performance.now();
        const star_path = path.join(__dirname, 'star_data.bin');
        const star_stat = await stat(star_path);
        const star_bin_stream = fs.createReadStream(star_path, { highWaterMark: 13 * 100 });
        res.writeHead(200, {
            'Content-Type': 'application/octet-stream',
            'Content-Length': star_stat.size,
            'Transfer-Encoding': 'chunked',
        });

        star_bin_stream.on('data', chunk => {
            res.write(chunk);
        });

        star_bin_stream.on('end', () => {
            res.end();
            const response_end = performance.now();
            console.log(`Sending stars took ${response_end - response_start} ms`);
        });
    });

    app.get('/constellations', (req, res) => {
        res.writeHead(200, {
            'Content-Type': 'application/octet-stream',
            'Content-Length': const_bin.buffer.byteLength,
        });

        res.write(const_bin);
        res.end();
    });

    app.get('/constellations/meta', (req, res) => {
        res.send(constellations);
    });

    http.createServer(app).listen(PORT, HOST, () => console.log(`Listening on port ${PORT}`));
};

main();
