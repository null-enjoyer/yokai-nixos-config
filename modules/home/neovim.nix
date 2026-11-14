{ config, pkgs, lib, ... }:
{
  # Leader = <Space>.
  # Keymaps cheat-sheet:
  #   <Space>ff  find files          <Space>fg  live grep
  #   <Space>fb  buffers             <Space>fh  help tags
  #   <Space>e   toggle file tree    <C-h/j/k/l> move between splits
  #   gd hover/K/<Space>rn/<Space>ca — standard LSP (defined per-buffer on attach)
  #   <C-Space> trigger completion   <C-y> confirm completion
  programs.neovim = {
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    plugins = with pkgs.vimPlugins; [
      # Tokyo Night editor theme.
      {
        plugin = tokyonight-nvim;
        type = "lua";
        config = "vim.cmd.colorscheme('tokyonight-night')";
      }

      # Tree-sitter for proper syntax highlighting
      {
        plugin = nvim-treesitter.withPlugins (p: [
          p.lua p.nix p.bash p.python p.javascript p.typescript p.tsx
          p.rust p.go p.json p.yaml p.toml p.markdown p.markdown_inline
          p.html p.css
        ]);
        type = "lua";
        config = ''
          -- withPlugins supplies parsers on the runtimepath. Enable highlighting
          -- and indentation per buffer through the FileType autocmd.
          require('nvim-treesitter').setup({})

          vim.api.nvim_create_autocmd('FileType', {
            callback = function(args)
              local lang = vim.treesitter.language.get_lang(vim.bo[args.buf].filetype)
              if lang and pcall(vim.treesitter.start, args.buf, lang) then
                vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
              end
            end,
          })
        '';
      }

      # Telescope: fuzzy-finder over files, grep, buffers, help
      plenary-nvim
      nvim-web-devicons
      {
        plugin = telescope-nvim;
        type = "lua";
        config = ''
          local t = require('telescope.builtin')
          vim.keymap.set('n', '<leader>ff', t.find_files, { desc = 'Find files' })
          vim.keymap.set('n', '<leader>fg', t.live_grep,  { desc = 'Live grep'  })
          vim.keymap.set('n', '<leader>fb', t.buffers,    { desc = 'Buffers'    })
          vim.keymap.set('n', '<leader>fh', t.help_tags,  { desc = 'Help tags'  })
        '';
      }

      # File tree
      {
        plugin = nvim-tree-lua;
        type = "lua";
        config = ''
          require('nvim-tree').setup({})
          vim.keymap.set('n', '<leader>e', ':NvimTreeToggle<CR>', { desc = 'Toggle file tree' })
        '';
      }

      # Statusline
      {
        plugin = lualine-nvim;
        type = "lua";
        config = "require('lualine').setup({ options = { theme = 'tokyonight' } })";
      }

      # Git signs in the gutter
      {
        plugin = gitsigns-nvim;
        type = "lua";
        config = "require('gitsigns').setup()";
      }

      # Add language servers to extraPackages and vim.lsp.enable together.
      {
        plugin = nvim-lspconfig;
        type = "lua";
        config = ''
          vim.lsp.enable({
            'nil_ls',        -- Nix
            'lua_ls',        -- Lua
            'ts_ls',         -- JS / TS
            'pyright',       -- Python
            'gopls',         -- Go
            'rust_analyzer', -- Rust
          })

          -- LSP keymaps activate per-buffer when a server attaches.
          vim.api.nvim_create_autocmd('LspAttach', {
            callback = function(args)
              local buf = args.buf
              vim.keymap.set('n', 'gd',         vim.lsp.buf.definition,  { buffer = buf, desc = 'Go to definition' })
              vim.keymap.set('n', 'K',          vim.lsp.buf.hover,       { buffer = buf, desc = 'Hover' })
              vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename,      { buffer = buf, desc = 'Rename' })
              vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { buffer = buf, desc = 'Code action' })
              vim.keymap.set('n', 'gr',         vim.lsp.buf.references,  { buffer = buf, desc = 'References' })
            end,
          })
        '';
      }

      # In-buffer Markdown rendering (headings, code blocks, tables, checkboxes…)
      # Renders in Normal mode; falls back to raw text in Insert mode / on the cursor line.
      {
        plugin = render-markdown-nvim;
        type = "lua";
        config = ''
          require('render-markdown').setup({})
          vim.keymap.set('n', '<leader>tm', '<cmd>RenderMarkdown toggle<CR>', { desc = 'Toggle markdown render' })
        '';
      }

      # Autocompletion
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      {
        plugin = nvim-cmp;
        type = "lua";
        config = ''
          local cmp = require('cmp')
          cmp.setup({
            mapping = cmp.mapping.preset.insert({
              ['<C-Space>'] = cmp.mapping.complete(),
              ['<C-y>']     = cmp.mapping.confirm({ select = true }),
              ['<Tab>']     = cmp.mapping.select_next_item(),
              ['<S-Tab>']   = cmp.mapping.select_prev_item(),
            }),
            sources = {
              { name = 'nvim_lsp' },
              { name = 'buffer'   },
              { name = 'path'     },
            },
          })
        '';
      }
    ];

    initLua = ''
      -- Leader = space
      vim.g.mapleader = ' '
      vim.g.maplocalleader = ' '

      local opt = vim.opt
      opt.number = true
      opt.relativenumber = true
      opt.expandtab = true
      opt.shiftwidth = 2
      opt.tabstop = 2
      opt.smartindent = true
      opt.termguicolors = true
      opt.cursorline = true
      opt.signcolumn = 'yes'
      opt.scrolloff = 8
      opt.ignorecase = true
      opt.smartcase = true
      opt.undofile = true
      opt.mouse = 'a'
      opt.clipboard = 'unnamedplus'

      -- Move between splits without the <C-w> prefix
      vim.keymap.set('n', '<C-h>', '<C-w>h')
      vim.keymap.set('n', '<C-j>', '<C-w>j')
      vim.keymap.set('n', '<C-k>', '<C-w>k')
      vim.keymap.set('n', '<C-l>', '<C-w>l')

      -- Clear search highlight
      vim.keymap.set('n', '<Esc>', ':nohlsearch<CR>', { silent = true })
    '';

    # External binaries the plugins need at runtime.
    extraPackages = with pkgs; [
      # Language servers
      nil                          # Nix
      lua-language-server          # Lua
      typescript-language-server   # JS / TS
      pyright                      # Python
      gopls                        # Go
      rust-analyzer                # Rust

      # Telescope backends
      fd
      ripgrep
    ];
  };
}
