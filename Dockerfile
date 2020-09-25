FROM nvidia/cuda:10.2-cudnn8-runtime-ubuntu18.04
LABEL authors="fanfanzhisu"
RUN chmod 1777 /tmp && chmod 1777 /var/tmp

ARG NB_USER="ffzs"
ARG NB_UID="1000"
ARG NB_GID="100"
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
USER root

ENV DEBIAN_FRONTEND noninteractive
RUN rm /etc/apt/sources.list.d/cuda.list /etc/apt/sources.list.d/nvidia-ml.list && \
    apt-get update && \
    apt-get install -yq --no-install-recommends \
    wget \
    bzip2 \
    ca-certificates \
    sudo \
    locales \
    fonts-liberation \
    run-one && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen


## 添加环境 home路径 conda路径
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    NB_USER=$NB_USER \
    NB_UID=$NB_UID \
    NB_GID=$NB_GID \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV PATH=$CONDA_DIR/bin:$PATH \
    HOME=/home/$NB_USER

## 复制一个脚本用于更改权限
COPY fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

# 命令行显示颜色
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc

# 创建用户
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    mkdir -p $CONDA_DIR && \
    chown $NB_USER:$NB_GID $CONDA_DIR && \
    chmod g+w /etc/passwd && \
    fix-permissions $HOME && \
    fix-permissions $CONDA_DIR


####### 安装 miniconda #########

USER $NB_UID
WORKDIR $HOME
ARG PYTHON_VERSION=default

# 设置工作目录
RUN mkdir /home/$NB_USER/work && \
    fix-permissions /home/$NB_USER

# 下载miniconda 并通过md5校验， 使用用户安装conda
ENV MINICONDA_VERSION=4.8.3 \
    MINICONDA_MD5=751786b92c00b1aeae3f017b781018df \
    CONDA_VERSION=4.8.3

WORKDIR /tmp
RUN wget --quiet https://repo.continuum.io/miniconda/Miniconda3-py37_${MINICONDA_VERSION}-Linux-x86_64.sh && \
    echo "${MINICONDA_MD5} *Miniconda3-py37_${MINICONDA_VERSION}-Linux-x86_64.sh" | md5sum -c - && \
    /bin/bash Miniconda3-py37_${MINICONDA_VERSION}-Linux-x86_64.sh -f -b -p $CONDA_DIR && \
    rm Miniconda3-py37_${MINICONDA_VERSION}-Linux-x86_64.sh && \
    echo "conda ${CONDA_VERSION}" >> $CONDA_DIR/conda-meta/pinned && \
    conda config --system --prepend channels conda-forge && \
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true && \
    conda config --system --set channel_priority strict && \
    if [ ! $PYTHON_VERSION = 'default' ]; then conda install --yes python=$PYTHON_VERSION; fi && \
    conda list python | grep '^python ' | tr -s ' ' | cut -d '.' -f 1,2 | sed 's/$/.*/' >> $CONDA_DIR/conda-meta/pinned && \
    conda install --quiet --yes conda && \
    conda install --quiet --yes pip && \
    conda update --all --quiet --yes && \
    conda clean --all -f -y && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

# 安装 Tini
RUN conda install --quiet --yes 'tini=0.18.0' && \
    conda list tini | grep tini | tr -s ' ' | cut -d ' ' -f 1,2 >> $CONDA_DIR/conda-meta/pinned && \
    conda clean --all -f -y && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

######  安装 jupyter #######
# Copyright (c) Jupyter Development Team.
# 安装 Jupyter Notebook, Lab, and Hub
# 
LABEL maintainer="Jupyter Project <jupyter@googlegroups.com>"
RUN conda install --quiet --yes \
    'notebook=6.0.3' \
    'jupyterhub=1.1.0' \
    'jupyterlab=2.1.3' && \
    conda clean --all -f -y && \
    npm cache clean --force && \
    jupyter notebook --generate-config && \
    rm -rf $CONDA_DIR/share/jupyter/lab/staging && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

EXPOSE 8888

# Configure container startup
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]

# Copy local files as late as possible to avoid cache busting
COPY start.sh start-notebook.sh start-singleuser.sh /usr/local/bin/
COPY jupyter_notebook_config.py /etc/jupyter/

# Fix permissions on /etc/jupyter as root
USER root
RUN fix-permissions /etc/jupyter/

# 安装运行使用的软件
RUN apt-get update && apt-get install -yq --no-install-recommends \
    build-essential \
    emacs-nox \
    vim-tiny \
    git \
    inkscape \
    jed \
    libsm6 \
    libxext-dev \
    libxrender1 \
    lmodern \
    netcat \
    python-dev \
    # ---- nbconvert dependencies ----
    texlive-xetex \
    texlive-fonts-recommended \
    texlive-plain-generic \
    texlive-fonts-extra \
    tzdata \
    unzip \
    nano \
    # ffmpeg for matplotlib anim & dvipng for latex labels
    ffmpeg \
    dvipng \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

USER $NB_UID

# 安装python常用包
RUN conda install --quiet --yes \
    'beautifulsoup4=4.9.*' \
    'conda-forge::blas=*=openblas' \
    'bokeh=2.0.*' \
    'bottleneck=1.3.*' \
    'cloudpickle=1.4.*' \
    'cython=0.29.*' \
    'dask=2.15.*' \
    'dill=0.3.*' \
    'h5py=2.10.*' \
    'hdf5=1.10.*' \
    'ipywidgets=7.5.*' \
    'ipympl=0.5.*'\
    'matplotlib-base=3.2.*' \
    'numba=0.48.*' \
    'numexpr=2.7.*' \
    'pandas=1.0.*' \
    'patsy=0.5.*' \
    'protobuf=3.11.*' \
    'pytables=3.6.*' \
    'scikit-image=0.16.*' \
    'scikit-learn=0.22.*' \
    'scipy=1.4.*' \
    'seaborn=0.10.*' \
    'sqlalchemy=1.3.*' \
    'statsmodels=0.11.*' \
    'sympy=1.5.*' \
    'vincent=0.4.*' \
    'widgetsnbextension=3.5.*'\
    'xlrd=1.2.*' \
    && \
    conda clean --all -f -y && \
    # 激活ipywidgets extension
    jupyter nbextension enable --py widgetsnbextension --sys-prefix && \
    # 激活 ipywidgets extension for JupyterLab
    jupyter labextension install @jupyter-widgets/jupyterlab-manager@^2.0.0 --no-build && \
    jupyter labextension install @bokeh/jupyter_bokeh@^2.0.0 --no-build && \
    jupyter labextension install jupyter-matplotlib@^0.7.2 --no-build && \
    jupyter lab build -y && \
    jupyter lab clean -y && \
    npm cache clean --force && \
    rm -rf "${HOME}/.cache/yarn" && \
    rm -rf "${HOME}/.node-gyp" && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "${HOME}"

# 安装 facets facets项目包含两个用于理解和分析机器学习数据集的可视化
WORKDIR /tmp
RUN git clone https://github.com/PAIR-code/facets.git && \
    jupyter nbextension install facets/facets-dist/ --sys-prefix && \
    rm -rf /tmp/facets && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "${HOME}"

# 添加环境
ENV XDG_CACHE_HOME="${HOME}/.cache/"

RUN MPLBACKEND=Agg python -c "import matplotlib.pyplot" && \
    fix-permissions "${HOME}"

#### 安装 jupyter 插件 ###
USER root
RUN pip install --no-cache-dir ipyleaflet plotly==4.8.* "ipywidgets>=7.5"

# 安装 Graphviz
RUN set -ex \
 && buildDeps=' \
    graphviz==0.11 \
' \
 && apt-get update \
 && apt-get -y install htop apt-utils graphviz libgraphviz-dev openssh-client \
 && pip install --no-cache-dir $buildDeps

RUN fix-permissions $CONDA_DIR
RUN jupyter labextension install @jupyterlab/github
RUN jupyter labextension install jupyterlab-drawio
RUN jupyter labextension install jupyter-leaflet
RUN jupyter labextension install jupyterlab-plotly@4.8.1
RUN jupyter labextension install @jupyter-widgets/jupyterlab-manager
RUN pip install --no-cache-dir jupyter-tabnine==1.0.2  && \
    jupyter nbextension install --py jupyter_tabnine && \
    jupyter nbextension enable --py jupyter_tabnine && \
    jupyter serverextension enable --py jupyter_tabnine
RUN pip install --no-cache-dir jupyter_contrib_nbextensions \
    jupyter_nbextensions_configurator rise && \
    jupyter nbextension enable codefolding/main
RUN jupyter labextension install @ijmbarr/jupyterlab_spellchecker

RUN fix-permissions /home/$NB_USER

USER $NB_UID

# 复制 jupyter_notebook_config.json 
COPY jupyter_notebook_config.json /etc/jupyter/

WORKDIR $HOME
##### 安装 pytorch #####
# Install PyTorch with dependencies

RUN conda install --quiet --yes \
    pyyaml mkl mkl-include setuptools cmake cffi typing \
    pytorch \ 
    torchvision \
    cudatoolkit=10.2 -c pytorch

RUN conda clean --all -f -y && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

##### 安装 mxnet 和 d2l  #### 
RUN pip install --upgrade pip && \
    pip install --no-cache-dir "d2l" 

RUN pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple && \
    pip config set global.timeout 60000 && \
    pip install --no-cache-dir "mxnet-cu102==1.7.0" && \
    pip config unset global.index-url


