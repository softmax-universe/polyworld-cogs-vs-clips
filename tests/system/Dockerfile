FROM python:3.12-slim
RUN pip install --no-cache-dir websockets==16.1.1
COPY tests/system/docker_players.py /app/player.py
CMD ["python", "/app/player.py", "--player"]
