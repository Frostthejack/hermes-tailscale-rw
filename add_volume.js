const { execSync } = require('child_process');

// Create volume using Railway CLI with explicit environment
const result = execSync('railway volume add -m /hermes-data --json', {
  encoding: 'utf8',
  env: { ...process.env, MSYS_NO_PATHCONVERSION: '1' },
  timeout: 30000
});
console.log(result);
