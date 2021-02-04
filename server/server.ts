import express from 'express';
import bodyParser from 'body-parser';
import http from 'http';
import fs, { read } from 'fs';
import path from 'path';

enum SpectralType {
    O = 0,
    B = 1,
    A = 2,
    F = 3,
    G = 4,
    K = 5,
    M = 6,
}

interface Star {
    name: string;
    right_ascension: number;
    declination: number;
    brightness: number;
    spec_type: SpectralType;
}

interface SkyCoord {
    right_ascension: number;
    declination: number;
}

interface Constellation {
    name: string;
    boundaries: SkyCoord[];
}

const PORT = 8080;
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

const parseCatalogLine = (line: string): Star | null => {
    const data_values = line.split('|');
    let result: Star = {
        name: '',
        right_ascension: 0,
        declination: 0,
        brightness: 0,
        spec_type: 0,
    };
    let current_entry = 0;
    for (const entry of data_values) {
        if (current_entry > 14) break;
        switch (current_entry) {
            case 0:
                result.name = entry;
                break;
            case 1:
                try {
                    result.right_ascension = parseFloat(entry);
                } catch (err) {
                    return null;
                }
                break;
            case 5:
                try {
                    result.declination = parseFloat(entry);
                } catch (err) {
                    return null;
                }
                break;
            case 13:
                try {
                    const v_mag = parseFloat(entry);
                    const dimmest_visible = 18.6;
                    const brightest_value = -4.6;
                    const mag_display_factor = (dimmest_visible - (v_mag - brightest_value)) / dimmest_visible;
                    result.brightness = mag_display_factor;
                } catch (err) {
                    return null;
                }
                break;
            case 14:
                const type = entry.charAt(0).toLowerCase();
                if (type === 'o') {
                    result.spec_type = SpectralType.O;
                } else if (type === 'b') {
                    result.spec_type = SpectralType.B;
                } else if (type === 'a') {
                    result.spec_type = SpectralType.A;
                } else if (type === 'f') {
                    result.spec_type = SpectralType.F;
                } else if (type === 'g') {
                    result.spec_type = SpectralType.G;
                } else if (type === 'k') {
                    result.spec_type = SpectralType.K;
                } else if (type === 'm') {
                    result.spec_type = SpectralType.M;
                } else {
                    // Default to white for now, probably should update later
                    result.spec_type = SpectralType.A;
                }
                break;
        }
        current_entry += 1;
    }

    return result;
};

const parseRightAscension = (ra: string): number => {
    // console.log('Getting right ascension from ', ra);
    const parts = ra.split(' ');
    const hours = parseInt(parts[0]);
    const minutes = parseInt(parts[1]);
    const seconds = parseFloat(parts[2]);

    const hours_deg = hours * 15;
    const minutes_deg = (minutes / 60) * 15;
    const seconds_deg = (seconds / 3600) * 15;

    return hours_deg + minutes_deg + seconds_deg;
};

const parseConstallations = (lines: string[]): Constellation[] => {
    const constellations: Constellation[] = [];
    // let current_constellation_name: string = '';
    let current_constellation: Constellation | null = null;
    for (const line of lines) {
        // console.log('Parsing constellation line ', line);
        if (line.startsWith('#')) {
            continue;
        }
        const parts: string[] = line.split('|');
        if (current_constellation == null) {
            current_constellation = {
                name: parts[0],
                boundaries: [],
            };
        } else if (parts[0] !== current_constellation?.name) {
            constellations.push(current_constellation);
            current_constellation = {
                name: parts[0],
                boundaries: [],
            };
        }

        const coord: SkyCoord = {
            right_ascension: parseRightAscension(parts[1]),
            declination: parseFloat(parts[2]),
        };

        current_constellation.boundaries.push(coord);
    }

    constellations.push(current_constellation!);
    return constellations;
};

const stars: Promise<Star[]> = readFile(path.join(__dirname, 'sao_catalog'))
    .then(catalog =>
        catalog
            .toString()
            .split('\n')
            .filter(line => line.startsWith('SAO'))
    )
    .then(lines => lines.map(parseCatalogLine).filter(star => star != null) as Star[]);

const readConstellationFile = readFile(path.join(__dirname, 'constellations.txt'));

const constellations: Promise<Constellation[]> = readConstellationFile
    .then(catalog => catalog.toString().split('\n'))
    .then(lines => parseConstallations(lines));

const constellation_info: Promise<string[]> = readConstellationFile
    .then(catalog => catalog.toString().split('\n'))
    .then(lines => lines.filter(line => line.startsWith('#')))
    .then(lines => lines.map(line => line.substring(2)));

app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
});

app.get('/stars', async (req, res) => {
    const brightness_param = (req.query.brightness as string) ?? '0.31';
    const min_brightness = parseFloat(brightness_param);
    const available_stars = await stars;
    res.send(available_stars.filter(star => star.brightness >= min_brightness));
});

app.get('/constellation/bounds', async (req, res) => {
    res.send(await constellations);
});

app.get('/constellation/info', async (req, res) => {
    res.send(await constellation_info);
});

http.createServer(app).listen(PORT, () => console.log(`Listening on port ${PORT}`));
