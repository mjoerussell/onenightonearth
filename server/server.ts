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

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.get('/stars', async (req, res) => {
  const brightness_param = (req.query.brightness as string) ?? '0.33';
  const min_brightness = parseFloat(brightness_param);
  const available_stars = await stars;
  res.send(available_stars.filter(star => star.brightness >= min_brightness));
});

http.createServer(app).listen(PORT, () => console.log(`Listening on port ${PORT}`));
