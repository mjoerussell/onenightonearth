import http, { IncomingMessage, ServerResponse } from 'http';
import fs from 'fs';
import path from 'path';
import { performance } from 'perf_hooks';
import { readFile, readDir, stat } from './fs-util';

type SkyFile = Record<string, string>;

interface Constellation {
    name: string;
    epithet: string;
}

const PORT = 8080;
const HOST = process.env['HOST'] ?? '0.0.0.0';

const static_assets = ['dist/bundle.js', 'styles/main.css', 'assets/favicon.ico', 'dist/wasm/bin/night-math.wasm'];

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
    const sky_files = await readDir(path.join(__dirname, '../..', 'prepare-data', 'constellations', 'iau'));
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

const getContentType = (file_path: string): string | null => {
    if (file_path.endsWith('.css')) {
        return 'text/css';
    }
    if (file_path.endsWith('.html')) {
        return 'text/html';
    }
    if (file_path.endsWith('.js')) {
        return 'application/javascript';
    }
    if (file_path.endsWith('.wasm')) {
        return 'application/wasm';
    }
    if (file_path.endsWith('.ico')) {
        return 'image/x-icon';
    }

    return null;
};

const handleStarsRequest = (res: ServerResponse): void => {
    const response_start = performance.now();
    const star_path = path.join(__dirname, '..', 'star_data.bin');
    stat(star_path).then(star_stat => {
        const star_bin_stream = fs.createReadStream(star_path, { highWaterMark: 13 * 100 });
        res.writeHead(200, {
            'Content-Type': 'application/octet-stream',
            'Transfer-Encoding': 'chunked',
            'Content-Length': star_stat.size,
            'X-Content-Length': star_stat.size,
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
};

const handleStaticAssetRequest = (req: IncomingMessage, res: ServerResponse): void => {
    let found_asset: boolean = false;
    for (const asset of static_assets) {
        if (req.url!.endsWith(asset)) {
            found_asset = true;
            const asset_path = path.join(__dirname, '../../web', req.url!);
            stat(asset_path).then(file_stat => {
                if (file_stat.isFile()) {
                    const content_type = getContentType(asset_path);
                    if (content_type != null) {
                        readFile(asset_path)
                            .then(file => {
                                res.writeHead(200, {
                                    'Content-Type': content_type,
                                    'Content-Length': file.byteLength,
                                });
                                res.write(file);
                                res.end();
                            })
                            .catch(err => {
                                console.error('Error reading file ', asset_path.toString());
                                console.error(err);

                                res.writeHead(500);
                                res.end();
                            });
                    }
                } else {
                    res.writeHead(404);
                    res.end();
                }
            });
        }
    }

    if (!found_asset) {
        res.writeHead(404);
        res.end();
    }
};

const main = async () => {
    const const_bin = await readFile(path.join(__dirname, '..', 'const_data.bin'));

    const const_parse_start = performance.now();
    const constellations: Constellation[] = await readConstellationFiles();
    const const_parse_end = performance.now();

    console.log(`Constellation parsing took ${const_parse_end - const_parse_start} ms`);
    const requestListener = (req: IncomingMessage, res: ServerResponse) => {
        if (req.url == null) return;

        switch (req.url) {
            case '/':
                readFile(path.join(__dirname, '../../web', 'index.html')).then(index_file => {
                    res.writeHead(200, {
                        'Content-Type': 'text/html',
                    });
                    res.write(index_file);
                    res.end();
                });
                break;
            case '/stars':
                handleStarsRequest(res);
                break;
            case '/constellations':
                res.writeHead(200, {
                    'Content-Type': 'application/octet-stream',
                    'Content-Length': const_bin.buffer.byteLength,
                });

                res.write(const_bin);
                res.end();
                break;
            case '/constellations/meta':
                res.write(JSON.stringify(constellations));
                res.end();
                break;
            default:
                handleStaticAssetRequest(req, res);
        }
    };
    http.createServer(requestListener).listen(PORT, HOST, () => console.log(`Listening on port ${PORT}`));
};

main();
