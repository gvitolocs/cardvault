module.exports = {
  apps: [
    {
      name: 'pokoin-oracle-api',
      script: 'server/oracle-api-server.js',
      instances: 1,
      exec_mode: 'fork',
      env: {
        NODE_ENV: 'production',
        PORT: process.env.PORT || process.env.ORACLE_API_PORT || '8080',
      },
    },
  ],
};
