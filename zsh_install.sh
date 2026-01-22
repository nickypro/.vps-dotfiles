#!/bin/bash
echo "Setting up environment..."
sudo apt update
sudo apt install -y zsh figlet 

# python environment setup stuff
curl -LsSf https://astral.sh/uv/install.sh | sh # install uv

# Clone dotfiles repository
cd ~
if [ ! -d "~/.arena_infra/dotfiles" ]; then
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
ln -sf ~/.arena_infra/dotfiles/.zshrc ~/.zshrc
ln -sf ~/.arena_infra/dotfiles/.vimrc ~/.vimrc
ln -sf ~/.arena_infra/dotfiles/.p10k.zsh ~/.p10k.zsh

# make zsh default
sudo chsh -s /usr/bin/zsh $USER

