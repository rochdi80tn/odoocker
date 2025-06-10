from odoo import models, api

class ProductTemplate(models.Model):
    _inherit = 'product.template'

    @api.model
    def default_get(self, fields):
        res = super().default_get(fields)
        res['uom_id'] = False  # No default, forces user to select
        res['categ_id'] = False  # No default, forces user to select
        res['invoice_policy'] = 'delivery'
        res['taxes_id'] = [(6, 0, [])]  # Clear customer taxes
        res['supplier_taxes_id'] = [(6, 0, [])]  # Clear vendor taxes
        res['available_in_pos'] = True
        res['is_storable'] = True
        return res
