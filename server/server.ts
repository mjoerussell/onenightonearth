import express from 'express';
import bodyParser from 'body-parser';
import http, { maxHeaderSize } from 'http';
import fs from 'fs';
import path from 'path';

type CatalogEntry = string;
type Degree = number;

interface StarCoord {
  rightAscension: Degree;
  declination: Degree;
}

interface StarEntry extends StarCoord {
  magnitude: number;
  name: string;
  constellation: string | null;
  consId: string | null;
}

interface ConstellationBranch {
  a: StarCoord;
  b: StarCoord;
}

interface ConstellationEntry {
  name: string;
  branches: ConstellationBranch[];
}

const getName = (entry: CatalogEntry): string => {
  return entry.substring(4, 14);
};

const getRightAscension = (entry: CatalogEntry): Degree => {
  const raHours = parseInt(entry.substring(75, 77));
  const raMinutes = parseInt(entry.substring(77, 79));
  const raSeconds = parseInt(entry.substring(79, 83));

  const totalRaMinutes = raMinutes + raSeconds / 60;
  const totalRaHours = raHours + totalRaMinutes / 60;

  return totalRaHours * 15;
};

const getDeclination = (entry: CatalogEntry): Degree => {
  const decSign = entry.substring(83, 84);
  const decDegrees = parseInt(entry.substring(84, 86));
  const decArcMinutes = parseInt(entry.substring(86, 88));
  const decArcSeconds = parseInt(entry.substring(88, 90));

  const totalDecArcMinutes = decArcMinutes + decArcSeconds / 60;
  const totalDecDegrees = decDegrees + totalDecArcMinutes / 60;

  if (decSign === '-') {
    return -totalDecDegrees;
  }

  return totalDecDegrees;
};

const getConstellation = (entry: CatalogEntry): string | null => {
  const constellation = entry.substring(11, 14);
  if (constellation.trim() !== '') {
    return constellation;
  }
  return null;
};

const getConstellationId = (entry: CatalogEntry): string | null => {
  const id = entry.substring(7, 11);
  if (id.trim() !== '') {
    return id.trim();
  }
  return null;
};

const getMagnitude = (entry: CatalogEntry): number => {
  const mag = parseFloat(entry.substring(102, 107));
  // mag -= 8;
  // mag = mag / -12;

  return 1 / mag;
};

const PORT = 8080;
const app = express();

app.use(express.static(path.join(__dirname, '../public')));
app.use(bodyParser.json());

const stars: StarEntry[] = fs
  .readFileSync('./sao_catalog')
  .toString()
  .split('\n')
  .slice(75)
  .filter(entry => entry.startsWith('SAO'))
  .map(entry => {
    const data = entry.split('|');
    try {
      const v_mag = parseFloat(data[13]);
    } catch (e) {
      console.error(`${data[13]} is not a valid float`);
    }
    const v_mag = parseFloat(data[13]);
    const dimmest_visible = 18.6;
    const brightest_value = -4.6;
    const mag_display_factor = (dimmest_visible - (v_mag - brightest_value)) / dimmest_visible;

    return {
      name: data[0],
      rightAscension: parseFloat(data[1]),
      declination: parseFloat(data[5]),
      magnitude: mag_display_factor,
      constellation: null,
      consId: null,
    };
    // return {
    //   rightAscension: getRightAscension(entry),
    //   declination: getDeclination(entry),
    //   magnitude: getMagnitude(entry),
    //   name: getName(entry),
    //   constellation: getConstellation(entry),
    //   consId: getConstellationId(entry),
    // };
  })
  .filter(star => star.magnitude > 0.25);

const getConstellations = (stars: StarEntry[]): ConstellationEntry[] => {
  const catalog = fs.readFileSync('./constellations.txt').toString();
  const constellations: ConstellationEntry[] = [];
  for (const constellation of catalog.split('\n')) {
    if (constellation.startsWith('#')) continue;

    const items = constellation.split('|');
    const name = items[0].toLowerCase();
    const branchEntries = items.slice(1).map(i => i.split(','));
    const branches: ConstellationBranch[] = [];

    for (const [aEntry, bEntry] of branchEntries) {
      let a: StarCoord | null = null;
      let b: StarCoord | null = null;
      for (const star of stars) {
        if (star.constellation?.toLowerCase() === name && star.consId?.toLowerCase() === aEntry.toLowerCase()) {
          a = {
            rightAscension: star.rightAscension,
            declination: star.declination,
          };
        }
        if (star.constellation?.toLowerCase() === name && star.consId?.toLowerCase() === bEntry.toLowerCase()) {
          b = {
            rightAscension: star.rightAscension,
            declination: star.declination,
          };
        }
      }
      if (a != null && b != null) {
        branches.push({ a, b });
      }
    }

    constellations.push({ name, branches });
  }

  return constellations;
};

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.get('/stars', (req, res) => {
  res.send(stars);
});

app.get('/constellations', (req, res) => {
  // res.send(getConstellations(stars));
  res.send([]);
});

http.createServer(app).listen(PORT, () => console.log(`Listening on port ${PORT}`));
