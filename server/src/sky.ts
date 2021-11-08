import path from 'path';
import { readDir, readFile } from './fs-util';

type SkyFile = Record<string, string>;

export interface Constellation {
    name: string;
    epithet: string;
}

/**
 * Parse a `.sky` file. The `.sky` format is a custom format, and is essentially a very simple key-value config file. It has a
 * couple of features:
 *
 * 1. @key = value : The @ denotes a new key. Everything after the `=` (minus leading/trailing whitespace) is treated as a string value
 * 2. @key |= value : Same as the previous one, except `|=` accepts a multiline string. The string continues until the next key.
 * 3. #tag : Basically just a key with no value. The value will be set to `'true'` (a string), but only the presence of the tag matters.
 * @param data The contents of a `.sky` file.
 * @returns The parsed data.
 */
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

/**
 * Read all of the `.sky` files in the default directory, parse them, and extract the `Constellation`
 * data from them.
 * @returns A Promise with a list of found constellations.
 */
export const readConstellationFiles = async (): Promise<Constellation[]> => {
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
