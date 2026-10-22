<?xml version="1.0"?>
<!--
     WSUS Offline Update - Verification Stylesheet: Windows 11 Product ID
     Category Product ID: 72e7624a-5b00-45d2-b92f-e561c0a6a160
-->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:__="http://schemas.microsoft.com/msus/2004/02/OfflineSync" version="1.0">
  <xsl:output omit-xml-declaration="yes" indent="no" method="text"/>
  <xsl:template match="/">
    <xsl:for-each select="__:OfflineSyncPackage/__:Updates/__:Update/__:Categories/__:Category[@Type='Product']">
      <xsl:if test="contains(@Id, '72e7624a-5b00-45d2-b92f-e561c0a6a160')">
        <xsl:if test="../../@RevisionId != '' and ../../@UpdateId != ''">
          <xsl:text>#</xsl:text>
          <xsl:value-of select="../../@RevisionId"/>
          <xsl:text>#,</xsl:text>
          <xsl:value-of select="../../@UpdateId"/>
          <xsl:text>&#10;</xsl:text>
        </xsl:if>
      </xsl:if>
    </xsl:for-each>
  </xsl:template>
</xsl:stylesheet>
