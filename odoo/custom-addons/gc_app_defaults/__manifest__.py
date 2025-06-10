{
    'name': 'GERA - APP defaults ',
    'version': '18.0.1.0.0',
    'summary': 'Setting defaults for Customers & Product POS/Tracking',
    'description': '...',
    'category': 'Accounting',
    'author': 'GERANIUM',
    'website': 'https://www.geranium.tn',
    'license': 'Other proprietary',
    "depends": ["base", "product", "point_of_sale", "stock"],
    'data': [],
    'installable': True,
    "post_init_hook": "set_customers_lang_to_fr",

}

