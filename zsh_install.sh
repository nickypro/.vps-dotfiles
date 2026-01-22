#!/bin/bash
echo "Setting up environment..."
sudo apt update
sudo apt install -y zsh figlet fzf btop tmux nvtop ncdu htop neofetch curl wget

# python environment setup stuff
curl -LsSf https://astral.sh/uv/install.sh | sh # install uv

# Clone dotfiles repository
cd ~
if [ ! -d "~/.vps-dotfiles" ]; then
  git clone https://github.com/nickypro/.vps-dotfiles ~/.vps-dotfiles
fi

# Install Oh My Zsh
CHSH=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Install Zsh plugins
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
git clone https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions

# Create symbolic links
ln -sf ~/.vps_dotfiles/.zshrc ~/.zshrc
ln -sf ~/.vps_dotfiles/.vimrc ~/.vimrc
ln -sf ~/.vps_dotfiles/.p10k.zsh ~/.p10k.zsh

# make zsh default
sudo chsh -s /usr/bin/zsh $USER

if [ -d /lambda ]; then
  echo "Lambda-ish machine, installing docker"
  sudo apt install -y wmdocker docker-compose
  sudo usermod -aG docker $USER
else
  echo "Non-Lambda machine, skipping docker installation"
fi

mkdir ~/.venv
uv venv
source ~/.venv/bin/activate
