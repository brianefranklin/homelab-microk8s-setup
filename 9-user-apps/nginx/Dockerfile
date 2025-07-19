# Use the official NGINX image as a base. This image is highly optimized
# and automatically starts the NGINX web server on port 80.
FROM nginx:mainline-alpine

# The NGINX image serves files from /usr/share/nginx/html by default.
# We will copy our custom index.html file into that directory.
# This proves that our custom image was built and deployed by the pipeline.
COPY index.html /usr/share/nginx/html/index.html

# No need for EXPOSE or CMD, as the base NGINX image already
# handles exposing port 80 and starting the web server.
EXPOSE  80