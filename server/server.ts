import express from 'express';
import bodyParser from 'body-parser';
import http from 'http';
import fs from 'fs';
import path from 'path';

interface Star {
  name: string;
  right_ascension: number;
  declination: number;
  brightness: number;
}

// interface StarEntry extends StarCoord {
//   magnitude: number;
//   name: string;
//   constellation: string | null;
//   consId: string | null;
// }

// interface ConstellationBranch {
//   a: StarCoord;
//   b: StarCoord;
// }

// interface ConstellationEntry {
//   name: string;
//   branches: ConstellationBranch[];
// }

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

// const getConstellations = (stars: StarEntry[]): ConstellationEntry[] => {
//   const catalog = fs.readFileSync('./constellations.txt').toString();
//   const constellations: ConstellationEntry[] = [];
//   for (const constellation of catalog.split('\n')) {
//     if (constellation.startsWith('#')) continue;

//     const items = constellation.split('|');
//     const name = items[0].toLowerCase();
//     const branchEntries = items.slice(1).map(i => i.split(','));
//     const branches: ConstellationBranch[] = [];

//     for (const [aEntry, bEntry] of branchEntries) {
//       let a: StarCoord | null = null;
//       let b: StarCoord | null = null;
//       for (const star of stars) {
//         if (star.constellation?.toLowerCase() === name && star.consId?.toLowerCase() === aEntry.toLowerCase()) {
//           a = {
//             rightAscension: star.rightAscension,
//             declination: star.declination,
//           };
//         }
//         if (star.constellation?.toLowerCase() === name && star.consId?.toLowerCase() === bEntry.toLowerCase()) {
//           b = {
//             rightAscension: star.rightAscension,
//             declination: star.declination,
//           };
//         }
//       }
//       if (a != null && b != null) {
//         branches.push({ a, b });
//       }
//     }

//     constellations.push({ name, branches });
//   }

//   return constellations;
// };

const parseCatalogLine = (line: string): Star | null => {
  const data_values = line.split('|');
  let result: Star = {
    name: '',
    right_ascension: 0,
    declination: 0,
    brightness: 0,
  };
  let current_entry = 0;
  for (const entry of data_values) {
    if (current_entry > 13) break;
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
    }
    current_entry += 1;
  }

  return result;
};

const stars: Promise<Star[]> = readFile(path.join(__dirname, 'sao_catalog'))
  .then(catalog =>
    catalog
      .toString()
      .split('\n')
      .filter(line => line.startsWith('SAO'))
  )
  .then(lines => lines.map(parseCatalogLine).filter(star => star != null) as Star[]);
// .then(stars => stars.filter(star => star.brightness > 0.33))
// .then(stars => stars.sort((a, b) => a.declination - b.declination));

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.get('/stars', async (req, res) => {
  const brightness_param = (req.query.brightness as string) ?? '0.33';
  const min_brightness = parseFloat(brightness_param);
  const available_stars = await stars;
  res.send(available_stars.filter(star => star.brightness >= min_brightness));
});

app.get('/constellations', (req, res) => {
  // res.send(getConstellations(stars));
  res.send([]);
});

http.createServer(app).listen(PORT, () => console.log(`Listening on port ${PORT}`));
