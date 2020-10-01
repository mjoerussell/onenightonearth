import express from 'express';
import bodyParser from 'body-parser';
import http from 'http';
import fs from 'fs';
import path from 'path';

type CatalogEntry = string;
type Degree = number;

interface StarEntry {
  rightAscension: Degree;
  declination: Degree;
  magnitude: number;
  name: string;
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

const getMagnitude = (entry: CatalogEntry): number => {
  let mag = parseFloat(entry.substring(102, 107));
  mag -= 8;
  mag = mag / -12;

  return mag;
};

const PORT = 8080;
const app = express();

app.use(express.static(path.join(__dirname, '../public')));
app.use(bodyParser.json());

const stars: StarEntry[] = fs
  .readFileSync('./catalog')
  .toString()
  .split('\n')
  .map(entry => {
    return {
      rightAscension: getRightAscension(entry),
      declination: getDeclination(entry),
      magnitude: getMagnitude(entry),
      name: getName(entry),
    };
  })
  .filter(star => star.magnitude > 0);

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.get('/stars', (req, res) => {
  res.send(stars);
});

http.createServer(app).listen(PORT, () => console.log(`Listening on port ${PORT}`));
