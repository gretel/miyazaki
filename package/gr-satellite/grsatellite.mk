################################################################################
#
# PACKAGE_GR_SATELLITE
#
################################################################################


GR_SATELLITE_VERSION = 9110aaefb0bdc27d4fde414bcc34c3670d916638

GR_SATELLITE_SITE = $(call github,daniestevez,gr-satellites,$(GR_SATELLITE_VERSION))
GR_SATELLITE_STAGING = YES

GR_SATELLITE_CONF_ENV += $(PKG_PYTHON_SETUPTOOLS_ENV)
$(eval $(cmake-package))

