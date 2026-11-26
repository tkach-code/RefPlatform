# Static landing page served by unprivileged nginx (runs as uid 101) on port 3000.
FROM nginxinc/nginx-unprivileged:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY public/ /usr/share/nginx/html/

EXPOSE 3000
