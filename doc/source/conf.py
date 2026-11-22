# Configuration file for the Sphinx documentation builder.
#
# For the full list of built-in configuration values, see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Project information -----------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#project-information
from __future__ import annotations

import os
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from sphinx.application import Sphinx
    from sphinx.ext.autodoc._property_types import _AutodocObjType

# EXTREMELY IMPORTANT: Ignore native module type stubs for autodoc
# This prevents Sphinx from trying to import type stubs for native modules,
# which will cause import errors with extensions that rely on native modules.
#
# This was added in https://github.com/sphinx-doc/sphinx/pull/13446 triggered
# by https://github.com/sphinx-doc/sphinx/issues/13415
#
# There is no documentation for this option, which would've saved hours of
# trying to monkeypatch things to work with Sphinx >= 8.0.
os.environ["SPHINX_AUTODOC_IGNORE_NATIVE_MODULE_TYPE_STUBS"] = "1"

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


def on_autodoc_process_signature(
    app: Sphinx,
    obj_type: _AutodocObjType,
    full_name: str,
    obj: object,
    options: object,
    signature: str,
    return_annotation: str | None,
):
    from cyndilib.discovery.types import (
        DiscoveredPeerT,
        DiscoveredReceiver,
        DiscoveredSender,
        ListenerEventT,
        ReceiveListenerEvent,
        SendListenerEvent,
    )

    if return_annotation is None:
        return signature, return_annotation
    if obj_type == "method":
        # Since we're using `:inherited-members:` to generate the docs from
        # their generic bases, remap the generics to their real types for clarity.
        if obj.__module__ != "cyndilib.discovery.base_listener":
            return signature, return_annotation

        # Use the imported class names to avoid losing sync if the code changes
        generic_names = {
            DiscoveredPeerT.__name__: {
                "SendListener": DiscoveredSender.__name__,
                "RecvListener": DiscoveredReceiver.__name__
            },
            ListenerEventT.__name__: {
                "SendListener": SendListenerEvent.__name__,
                "RecvListener": ReceiveListenerEvent.__name__,
            }
        }
        class_name = full_name.split('.')[-2]
        if class_name in ["SendListener", "RecvListener"]:
            for k, v in generic_names.items():
                if k in return_annotation:
                    return_annotation = return_annotation.replace(k, v[class_name])
                if k in signature:
                    signature = signature.replace(k, v[class_name])
        return signature, return_annotation



def setup(app: Sphinx):
    app.connect("autodoc-process-signature", on_autodoc_process_signature)


autodoc_member_order = 'bysource'
autodoc_default_options = {
    'show-inheritance':True,
}
autodoc_typehints = 'both'
autodoc_typehints_description_target = 'documented'
autodoc_docstring_signature = True

intersphinx_mapping = {
    'python':('https://docs.python.org/', None),
    'numpy':('https://numpy.org/doc/stable/', None),
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
