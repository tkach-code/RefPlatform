'use strict';

const express = require('express');

const router = express.Router();

router.post('/login', (req, res) => {
  const username = typeof req.body.username === 'string' ? req.body.username : '';
  console.log(`Login attempt with username: ${username}`);
  // req.baseUrl is the mount path (/empty-login).
  res.redirect(303, `${req.baseUrl}/home?username=${encodeURIComponent(username)}`);
});

module.exports = router;
