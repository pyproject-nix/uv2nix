from setuptools import setup

setup(
    name="legacy-package",
    version="0.1.0",
    packages=["legacy_package"],
    author="Your Name",
    author_email="your.email@example.com",
    description="A basic setup.py for legacy-package",
    url="https://example.com/legacy-package",
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
    ],
    python_requires=">=3.6",
    install_requires=["arpeggio"],
)
