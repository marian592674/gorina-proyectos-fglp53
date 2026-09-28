#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
menu_envio_informes.py — Menu interactivo para forzar envio manual de informes de Ciclo 3.
"""
import os, sys, datetime, subprocess

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PYTHON_EXE = sys.executable

def clear():
    os.system('cls' if os.name == 'nt' else 'clear')

def get_destinatario_input(default_to="informes.ciclo3@friggorina.com"):
    print()
    print(f"Destinatario oficial configurado: {default_to}")
    user_input = input("Presione ENTER para usar el destinatario oficial, o escriba un mail alternativo: ").strip()
    if user_input and '@' in user_input:
        print(f"-> Se enviara a: {user_input}")
        return user_input
    print(f"-> Se enviara a: {default_to}")
    return None

def ejecutar_script(script_name, extra_args):
    cmd = [PYTHON_EXE, os.path.join(BASE_DIR, script_name)] + extra_args
    print()
    print(f"Ejecutando: {' '.join(cmd)}")
    print("-" * 75)
    ret = subprocess.run(cmd)
    print("-" * 75)
    return ret.returncode

def main_menu():
    while True:
        clear()
        print("=" * 78)
        print("         FRIGORIFICO GORINA — CONTROL DE OPERACIONES CICLO 3")
        print("              MENU DE ENVIO MANUAL / FORZADO DE INFORMES")
        print("=" * 78)
        now_str = datetime.datetime.now().strftime("%d/%m/%Y %H:%M:%S")
        print(f"Fecha y Hora: {now_str}")
        print()
        print("Seleccione el informe que desea emitir:")
        print()
        print("  [1] Enviar Correo Diario de Cierre de Operaciones")
        print("      (Tabla resumen de producción TRV1/Crane + Excel oficial de Stock 8090)")
        print()
        print("  [2] Enviar Informe Semanal")
        print("      (PDF de todas las pestañas de Ciclo 3 en Legal)")
        print()
        print("  [3] Enviar Informe Mensual")
        print("      (PDF de todas las pestañas de Ciclo 3 en Legal)")
        print()
        print("  [4] Enviar Cierre Diario + Informes de Hoy segun calendario")
        print("      (Simula el cese de produccion diario y evalua calendario)")
        print()
        print("  [5] Modo Prueba / Simulacion (Genera archivos SIN enviar correos)")
        print()
        print("  [0] Salir")
        print("=" * 78)
        
        opc = input("Ingrese su opcion [0-5]: ").strip()
        
        if opc == '0':
            print("Saliendo...")
            break
        
        elif opc == '1':
            to = get_destinatario_input()
            args = ['--force']
            if to:
                args += ['--to', to]
            ejecutar_script('cierre_jornada.py', args)
            input("\nPresione ENTER para continuar...")

        elif opc == '2':
            to = get_destinatario_input()
            args = ['--weekly', '--force']
            if to:
                args += ['--to', to]
            ejecutar_script('envio_informe.py', args)
            input("\nPresione ENTER para continuar...")

        elif opc == '3':
            to = get_destinatario_input()
            args = ['--monthly', '--force']
            if to:
                args += ['--to', to]
            ejecutar_script('envio_informe.py', args)
            input("\nPresione ENTER para continuar...")

        elif opc == '4':
            to = get_destinatario_input()
            args = ['--force']
            if to:
                args += ['--to', to]
            ejecutar_script('cierre_jornada.py', args)
            input("\nPresione ENTER para continuar...")

        elif opc == '5':
            print("\n--- EJECUTANDO SIMULACION EN MODO TEST ---")
            ejecutar_script('cierre_jornada.py', ['--test', '--force'])
            ejecutar_script('envio_informe.py', ['--weekly', '--test'])
            ejecutar_script('envio_informe.py', ['--monthly', '--test'])
            input("\nPresione ENTER para continuar...")

        else:
            print("Opcion no valida.")
            input("Presione ENTER para continuar...")

if __name__ == '__main__':
    main_menu()
