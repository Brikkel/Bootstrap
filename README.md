# Bootstrap

One command to set up a new machine with my dotfiles (macOS, Arch, Debian / Raspberry Pi OS):

```sh
curl -fsSL https://raw.githubusercontent.com/Brikkel/Bootstrap/main/install.sh | sh
```

It installs git + chezmoi, creates an SSH key for the machine, waits until that key is added
(GitLab account on personal machines, read-only deploy keys on work machines) and then runs
`chezmoi init --apply` against the private dotfiles repo.

This repo only holds a copy of `install.sh`; the dotfiles themselves are private.
