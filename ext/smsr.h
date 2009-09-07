/* 
Se encontraran las definiciones para la implementacion y manejo de funciones de envio, recepcion
y demas funciones que envuelven las distintas primitivas ofrecidas por GNOKII
*/

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>
#include "gnokii.h"

#define CONNECTIONS_MAX_LENGTH 500
#define MESSAGE_QTY_MAX 50

typedef struct {

	int activeconnect;
	struct gn_statemachine *connections[CONNECTIONS_MAX_LENGTH];
	gn_data *datag[CONNECTIONS_MAX_LENGTH];

} gn_connection;

typedef struct {
	int error;
	int index;
	char *date;
	char *status;
	char *source_number;
	char *text;
	char *type_sms;
} gn_message;

void busterminate(int idconn);

int businit(char *nameconn, char *archpath);

int send_sms(char *number, char *msj, char *smsc, int report, char *validity, int idconn);

int send_smsi(char *number, char *msj, char *smsc, int report, char *validity,struct gn_statemachine *state);

gn_message get_msj(int number, int idconn);

gn_message get_msji(int number,gn_connection *conn,int idconn);

int get_sms(int idconn);

int get_smsi(gn_connection *conn,int idconn);

float rf_level(int idconn);

float bat_level(int idconn);

char *substring(size_t start,size_t end,const char *cad,char *subcad, size_t size);

char *phoneModel(int idconn);

char *phoneManufacter(int idconn);

char *phoneRevSoft(int idconn);

char *phoneImei(int idconn);

int testconn(int idconn);

char *printError(int e);
