FROM node as build-env

RUN mkdir -p /home/docker

WORKDIR /home/docker

COPY . .

RUN  npm install hexo-cli -g && npm install -f

RUN hexo clean & hexo g
CMD sleep 5000000000000
# FROM nginx

# RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# WORKDIR /usr/share/nginx/html

# COPY --from=build-env /home/docker/public /usr/share/nginx/html

# EXPOSE 80
