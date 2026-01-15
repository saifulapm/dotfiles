#!/bin/bash
# Install default webapps (same as omarchy)

nova-webapp-install "HEY" https://app.hey.com HEY.png "nova-webapp-handler-hey %u" "x-scheme-handler/mailto"
nova-webapp-install "Basecamp" https://launchpad.37signals.com Basecamp.png
nova-webapp-install "WhatsApp" https://web.whatsapp.com/ WhatsApp.png
nova-webapp-install "Google Photos" https://photos.google.com/ "Google Photos.png"
nova-webapp-install "Google Contacts" https://contacts.google.com/ "Google Contacts.png"
nova-webapp-install "Google Messages" https://messages.google.com/web/conversations "Google Messages.png"
nova-webapp-install "Google Maps" https://maps.google.com "Google Maps.png"
nova-webapp-install "ChatGPT" https://chatgpt.com/ ChatGPT.png
nova-webapp-install "YouTube" https://youtube.com/ YouTube.png
nova-webapp-install "GitHub" https://github.com/ GitHub.png
nova-webapp-install "X" https://x.com/ X.png
nova-webapp-install "Figma" https://figma.com/ Figma.png
nova-webapp-install "Discord" https://discord.com/channels/@me Discord.png
nova-webapp-install "Zoom" https://app.zoom.us/wc/home Zoom.png "nova-webapp-handler-zoom %u" "x-scheme-handler/zoommtg;x-scheme-handler/zoomus"
nova-webapp-install "Fizzy" https://app.fizzy.do/ Fizzy.png
