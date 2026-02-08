# Configuration file for the Sphinx documentation builder.
#
# For the full list of built-in configuration values, see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Project information -----------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#project-information

project = 'cyndilib'
copyright = '2022, Matthew Reid'
author = 'Matthew Reid'

try:
    import importlib.metadata
    release = importlib.metadata.version(project)
except ImportError:
    release = '0.0.0'
version = release


import subprocess


try:
    # Get the current commit SHA
    commit_sha = subprocess.check_output(['git', 'rev-parse', 'HEAD']).strip().decode('ascii')
except (subprocess.CalledProcessError, FileNotFoundError, OSError):
    commit_sha = "main"  # Fallback if git is unavailable



repo_url = "https://github.com/cyndilib/cyndilib"

# -- General configuration ---------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#general-configuration

extensions = [
    'sphinx.ext.autodoc',
    'sphinx.ext.napoleon',
    'sphinx.ext.doctest',
    'sphinx.ext.viewcode',
    'sphinx.ext.intersphinx',
    'sphinx.ext.extlinks',
    # TODO: Re-enable after determining issues with import discovery in examples
    # 'sphinx_codeautolink',
]


autodoc_member_order = 'bysource'
autodoc_default_options = {
    'show-inheritance':True,
}
autodoc_typehints = 'both'
autodoc_typehints_description_target = 'documented'
autodoc_docstring_signature = True

intersphinx_mapping = {
    'python':('https://docs.python.org/', None),
}

extlinks = {
    'github_permalink': (f'{repo_url}/blob/{commit_sha}/%s', 'View source on GitHub: %s'),
}

templates_path = ['_templates']
exclude_patterns = []

rst_epilog = """

.. |NDI| replace:: NDI®

"""

codeautolink_custom_blocks = {
    "python3": None,
    "pycon3": "sphinx_codeautolink.clean_pycon",
}

# -- Options for HTML output -------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#options-for-html-output

html_theme = 'furo'
html_static_path = ['_static']
