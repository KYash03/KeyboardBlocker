# What it is:
It's a small macOS app that lets you disable your keyboard with a simple menu-bar toggle.

# How it works:
The app uses macOS’s accessibility APIs to intercept and block keyboard events. When activated, it creates an event tap that stops any keystrokes from reaching your system until you disable it again.

# Why I created it:
I built this because I needed a way to clean my keyboard without accidentally hitting keys. While there are other solutions out there, many are closed-source and I was concerned about privacy. It turned out to be a fun and relatively simple project, so I decided to share my open source version with everyone.
