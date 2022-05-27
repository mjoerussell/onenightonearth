import fs from 'fs';
import path from 'path';

/**
 * Wrapper over `fs.readFile` that uses a Promise instead of a callback.
 * @param path The path to read from.
 * @returns A Promise that resolves with the file contents as a buffer if successful, or rejects
 *      with the error otherwise.
 */
export const readFile = (path: string): Promise<Buffer> => {
    return new Promise((resolve, reject) => {
        fs.readFile(path, (error, data) => {
            if (error != null) {
                reject(error);
            }
            resolve(data);
        });
    });
};

/**
 * A wrapper over `fs.stat` that uses a Promise instead of a callback.
 * @param path The path to stat
 * @returns A Promise that resolves with the file or directory stat info if successful, or rejects
 *      with the error otherwise.
 */
export const stat = (path: string): Promise<fs.Stats> => {
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
export const readDir = (dir_path: string): Promise<string[]> => {
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
