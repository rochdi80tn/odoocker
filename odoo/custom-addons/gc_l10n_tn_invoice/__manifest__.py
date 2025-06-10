# Part of Odoo. See LICENSE file for full copyright and licensing details.
{
    'name': 'GERA - Invoice customization',
    'version': '18.0.1.0.0',
    'summary': 'Customizations for invoice',
    'description': '...',
    'category': 'Accounting',
    'author': 'GERANIUM',
    'website': 'https://www.geranium.tn',
    'license': 'Other proprietary',
    'countries': ['tn'],
    'depends': ['account'],
    'auto_install': ['account'],
    'data': [
        'report/report_invoice.xml',
    ],
    'installable': True,
}
