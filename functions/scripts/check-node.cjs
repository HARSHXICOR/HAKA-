const expectedMajor = 22;
const actualMajor = Number(process.versions.node.split(".")[0]);

if (actualMajor !== expectedMajor) {
  console.error(`Haka backend requires Node ${expectedMajor}. Current runtime: ${process.version}.`);
  process.exit(1);
}

console.log(`Node runtime verified: ${process.version}`);
