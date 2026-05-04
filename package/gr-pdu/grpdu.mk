################################################################################
#
# PACKAGE_GR_SATELLITE
#
################################################################################


GR_PDU_VERSION = 68984503712114bbabb4d6b8814d3997144f025b

GR_PDU_SITE = $(call github,sandialabs,gr-pdu_utils,$(GR_PDU_VERSION))
GR_PDU_STAGING = YES

#GR_PDU_CONF_ENV += $(PKG_PYTHON_SETUPTOOLS_ENV)
$(eval $(cmake-package))

