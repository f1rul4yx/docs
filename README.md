# Docs

Este es el repositorio que contiene el Markdown de mi web para generar posteriormente el HTML con Jekyll.

## Instalación de jekyll

```bash
sudo apt install ruby-full build-essential -y
echo '# Install Ruby Gems to ~/gems' >> ~/.bashrc
echo 'export GEM_HOME="$HOME/gems"' >> ~/.bashrc
echo 'export PATH="$HOME/gems/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
gem install jekyll bundler
bundle install    # Este comando se tiene que ejecutar dentro de la carpeta donde está todo el programa jekyll
```

## Regla de cron

Para que se ejecute el script `update.sh` cada 5 minutos y se apliquen así los cambios que se realicen en el repositorio, lo más fácil es hacer una tarea en cron:

```bash
crontab -e
*/5 * * * * ~/docs/tools/update.sh >> ~/update.log 2>&1
```
