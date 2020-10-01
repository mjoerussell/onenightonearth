"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
var express_1 = __importDefault(require("express"));
var body_parser_1 = __importDefault(require("body-parser"));
var http_1 = __importDefault(require("http"));
var fs_1 = __importDefault(require("fs"));
var path_1 = __importDefault(require("path"));
var getName = function (entry) {
    return entry.substring(4, 14);
};
var getRightAscension = function (entry) {
    var raHours = parseInt(entry.substring(75, 77));
    var raMinutes = parseInt(entry.substring(77, 79));
    var raSeconds = parseInt(entry.substring(79, 83));
    var totalRaMinutes = raMinutes + raSeconds / 60;
    var totalRaHours = raHours + totalRaMinutes / 60;
    return totalRaHours * 15;
};
var getDeclination = function (entry) {
    var decSign = entry.substring(83, 84);
    var decDegrees = parseInt(entry.substring(84, 86));
    var decArcMinutes = parseInt(entry.substring(86, 88));
    var decArcSeconds = parseInt(entry.substring(88, 90));
    var totalDecArcMinutes = decArcMinutes + decArcSeconds / 60;
    var totalDecDegrees = decDegrees + totalDecArcMinutes / 60;
    if (decSign === '-') {
        return -totalDecDegrees;
    }
    return totalDecDegrees;
};
var getMagnitude = function (entry) {
    var mag = parseFloat(entry.substring(102, 107));
    mag -= 8;
    mag = mag / -12;
    return mag;
};
var PORT = 8080;
var app = express_1.default();
app.use(express_1.default.static(path_1.default.join(__dirname, '../public')));
app.use(body_parser_1.default.json());
var stars = fs_1.default
    .readFileSync('./catalog')
    .toString()
    .split('\n')
    .map(function (entry) {
    return {
        rightAscension: getRightAscension(entry),
        declination: getDeclination(entry),
        magnitude: getMagnitude(entry),
        name: getName(entry),
    };
})
    .filter(function (star) { return star.magnitude > 0; });
app.get('/', function (req, res) {
    res.sendFile(path_1.default.join(__dirname, 'index.html'));
});
app.get('/stars', function (req, res) {
    res.send(stars);
});
http_1.default.createServer(app).listen(PORT, function () { return console.log("Listening on port " + PORT); });
