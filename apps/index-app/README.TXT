# Static Web

Minimal static website (plain HTML, CSS, JavaScript) served by nginx in Docker.

## Structure

```
.
├── Dockerfile
├── nginx.conf          # nginx server config
└── public/             # site root, served as-is
    ├── index.html
    ├── about.html
    ├── css/style.css
    └── js/main.js
```

## Build the image

```sh
docker build -t static-web .
```

## Run the container

```sh
docker run -d --name static-web -p 8080:3000 static-web
```

Open http://localhost:8080 (health: http://localhost:8080/api/health)

## Stop and remove

```sh
docker stop static-web
docker rm static-web
```

## Development without rebuilding

Mount the `public` folder so edits show up on page refresh:

```sh
docker run --rm -p 8080:3000 -v "$(pwd)/public:/usr/share/nginx/html:ro" static-web
```

(PowerShell: use `${PWD}/public` instead of `$(pwd)/public`.)
