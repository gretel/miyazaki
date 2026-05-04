################################################################################
#
# srt
#
################################################################################


SRT_VERSION = b6b4ae990daa8193625a4ddeaeaed03023b23125
SRT_SITE = $(call github,Haivision,srt,$(SRT_VERSION))
SRT_INSTALL_STAGING = YES
SRT_CONF_OPTS = -DENABLE_ENCRYPTION=OFF -DENABLE_STATIC=OFF

$(eval $(cmake-package))


