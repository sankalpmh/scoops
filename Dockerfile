FROM nginx:alpine
# Apply available Alpine security updates
RUN apk upgrade --no-cache
COPY . /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]