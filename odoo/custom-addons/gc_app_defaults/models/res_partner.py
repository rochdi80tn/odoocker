from odoo import models, api

class ResPartner(models.Model):
    _inherit = 'res.partner'

    @api.model
    def default_get(self, fields):
        res = super().default_get(fields)
        res['lang'] ='fr_FR'
        return res
        # This code sets the default language for new customers to French (fr_FR).
