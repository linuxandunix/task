docker run -d --restart=always -p 80:80 -p 443:443 \
  -v /etc/manh:/etc/manh \
  -v /etc/manh/data/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
  -v /etc/manh/data/nginx:/etc/nginx:ro \
  -v /etc/manh/data/nginx/data:/data \
  -v /etc/manh/data/nginx/log:/var/log/nginx \
  --name nginx nginx;