import * as esbuild from 'esbuild';
import * as path from 'path';

function getSettingsFromArguments() {
  return {
    watch: process.argv.includes('--watch'),
    production: process.argv.includes('--prod'),
  };
}

function getBuildConfig(settings, plugins = []) {
  return {
    entryPoints: ['src/index.ts'],
    bundle: true,
    sourcemap: settings.production !== true,
    minify: settings.production === true,
    outfile: path.join(process.cwd(), 'dist/bundle.js'),
    plugins,
  };
}

const settings = getSettingsFromArguments();

const plugins = [];
const config = getBuildConfig(settings, plugins);


if (settings.watch) {
  const context = await esbuild.context(config);
  await context.watch();
} else {
  await esbuild.build(config);  
}
