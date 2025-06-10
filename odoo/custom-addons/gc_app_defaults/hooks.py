from odoo import SUPERUSER_ID, api

def set_customers_lang_to_fr(env):
    partners = env['res.partner'].search([('customer_rank', '>', 0)])
    partners.write({'lang': 'fr_FR'})