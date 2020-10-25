import express from 'express';
import bodyParser from 'body-parser';
import http from 'http';
import fs from 'fs';
import path from 'path';

interface StarCoord {
  rightAscension: number;
  declination: number;
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

const PORT = 8080;
const app = express();

app.use(express.static(path.join(__dirname, '../public')));
app.use(bodyParser.json());

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

app.get('/constellations', (req, res) => {
  // res.send(getConstellations(stars));
  res.send([]);
});

http.createServer(app).listen(PORT, () => console.log(`Listening on port ${PORT}`));
