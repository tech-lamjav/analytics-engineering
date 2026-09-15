
    
    

with all_values as (

    select
        motivo_primario as value_field,
        count(*) as n_records

    from `smartbetting-dados`.`futebol`.`fact_value_funnel`
    group by motivo_primario

)

select *
from all_values
where value_field not in (
    'saida_nao_catalogada','sem_cobertura_pinnacle','valor_nao_estimavel','sem_liquidez','sem_edge','nota_abaixo_da_regua','sem_lado_apostado','linha_nao_meia','odd_dc_abaixo_do_minimo','conjunto_incompleto','sem_liquidez_estrita','odd_outlier','faixa_odd_fora'
)


